import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../providers/data_providers.dart';
import '../providers/settings_providers.dart';
import '../models/book.dart';
import 'calendar_page.dart';
import 'settings_page.dart';
import 'book_manage_page.dart';
import '../utils/amount_utils.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  String _timeRange = '本月'; // 本月/本年/全部
  bool _hideAmount = false;
  bool _isDark = false;
  String _amountMode = 'smart';
  // 数据加载版本号：连续增删改会并发触发多次 _loadData，只允许最后一次结果落盘，避免旧结果覆盖新数据
  int _loadToken = 0;
  Map<String, double> _incomeStats = {};
  Map<String, double> _expenseStats = {};
  List<Map<String, dynamic>> _monthlyTrend = [];
  bool _loading = true;
  bool _loadError = false;
  String _errorMsg = '';
  List<Book> _books = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    final books = await DatabaseService.instance.getBooks();
    if (mounted) setState(() => _books = books);
  }

  // isRefresh=true（下拉刷新/记账后回首页）时不显示全屏加载圈，
  // 保留列表子树，避免 RefreshIndicator 被整体替换而卡死/变灰。
  Future<void> _loadData({bool isRefresh = false}) async {
    final myToken = ++_loadToken;
    if (!isRefresh && mounted) {
      setState(() { _loading = true; _loadError = false; });
    }
    try {
      final now = DateTime.now();
      String? startDate, endDate;
      final bookId = ref.read(currentBookIdProvider);

      if (_timeRange == '本月') {
        startDate = '${now.year}-${now.month.toString().padLeft(2,'0')}-01';
        final lastDay = DateTime(now.year, now.month + 1, 0).day;
        endDate = '${now.year}-${now.month.toString().padLeft(2,'0')}-${lastDay.toString().padLeft(2,'0')}';
      } else if (_timeRange == '本年') {
        startDate = '${now.year}-01-01';
        endDate = '${now.year}-12-31';
      }

      // 三个查询并行，任一异常都会被 catch 兜住
      final result = await Future.wait([
        DatabaseService.instance.getIncomeStats(startDate: startDate, endDate: endDate, bookId: bookId),
        DatabaseService.instance.getExpenseStats(startDate: startDate, endDate: endDate, bookId: bookId),
        DatabaseService.instance.getMonthlyTrend(months: 12, bookId: bookId),
      ]);

      // 已有更新的加载请求发起时，丢弃本次过期结果，防止连续增删改下旧数据回覆盖新数据
      if (!mounted || myToken != _loadToken) return;
      if (mounted) {
        setState(() {
          _incomeStats = result[0] as Map<String, double>;
          _expenseStats = result[1] as Map<String, double>;
          _monthlyTrend = result[2] as List<Map<String, dynamic>>;
          _loading = false;
          _loadError = false;
          _errorMsg = '';
        });
      }
    } catch (e) {
      // 过期请求的异常直接忽略，避免误显错误页
      if (myToken != _loadToken) return;
      // 关键：无论是否报错都必须复位 _loading，杜绝一直转圈/灰屏
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = true;
          _errorMsg = e.toString();
        });
      }
    }
  }

  // 千分位 + 两位小数（不做万/亿缩写），供首页金额统一调用
  static String _group2(String fixed) {
    final neg = fixed.startsWith('-');
    final abs = neg ? fixed.substring(1) : fixed;
    final parts = abs.split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '${neg ? '-' : ''}$intPart.${parts.length > 1 ? parts[1] : '00'}';
  }

  String _fmt(double? v) {
    if (v == null) return '¥0.00';
    if (_hideAmount) return '******';
    return '¥${_group2(v.toStringAsFixed(2))}';
  }

  String _fmtShort(double? v, [String mode = 'smart']) {
    if (v == null) return '0.00';
    if (_hideAmount) return '**';
    return AmountUtils.format(v, mode);
  }

  @override
  Widget build(BuildContext context) {
    final hideAmount = ref.watch(amountPrivacyProvider);
    _hideAmount = hideAmount; // 同步全局状态到实例变量
    final amountMode = ref.watch(amountDisplayModeProvider);
    _amountMode = amountMode;
    _isDark = ref.watch(darkModeProvider); // 同步深色模式，用于卡片底色适配
    final currentBookId = ref.watch(currentBookIdProvider);
    final currentBook = _books.firstWhere((b) => b.id == currentBookId, orElse: () => Book(name: '默认账本', createdAt: ''));

    // 记账/删改后全局刷新信号触发：静默刷新，不显示全屏加载圈，保证首页实时更新
    ref.listen(refreshTriggerProvider, (previous, next) {
      if (previous != next) {
        _loadData(isRefresh: true);
        _loadBooks();
      }
    });
    // 监听账本切换（无论从首页切换器还是设置-账本管理切换，都要同时刷新数据与账本列表/标题）
    ref.listen(currentBookIdProvider, (previous, next) {
      if (previous != next) {
        _loadData();
        _loadBooks();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _showBookSwitcher(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(currentBook.name),
              const Icon(Icons.arrow_drop_down, size: 20),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(hideAmount ? Icons.visibility_off : Icons.visibility),
            onPressed: () => ref.read(amountPrivacyProvider.notifier).toggle(),
            tooltip: '金额隐私',
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CalendarPage())),
            tooltip: '日历视图',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
            tooltip: '设置',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError
              ? _buildErrorView()
              : RefreshIndicator(
                  onRefresh: () => _loadData(isRefresh: true),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _buildHeader(),
                      _buildStatsCards(),
                      _buildPaymentStatus(),
                      _buildChart(),
                      _buildRecentSummary(),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
    );
  }

  // 数据加载失败时的兜底视图：绝不留白/灰屏，提供一键重试
  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 56, color: AppTheme.textHint),
          const SizedBox(height: 12),
          const Text('数据加载出现问题', style: TextStyle(fontSize: 15, color: AppTheme.textSecondary)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(_errorMsg, style: const TextStyle(fontSize: 11, color: AppTheme.textHint), textAlign: TextAlign.center, maxLines: 3),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _loadData(),
            icon: const Icon(Icons.refresh),
            label: const Text('重新加载'),
          ),
        ],
      ),
    );
  }

  void _showBookSwitcher(BuildContext context) {
    final currentBookId = ref.read(currentBookIdProvider);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('切换账本', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ..._books.map((book) => ListTile(
              leading: Icon(
                book.id == currentBookId ? Icons.bookmark : Icons.book_outlined,
                color: book.id == currentBookId ? AppTheme.primaryGold : AppTheme.textHint,
              ),
              title: Text(book.name, style: TextStyle(fontWeight: book.id == currentBookId ? FontWeight.bold : FontWeight.normal)),
              trailing: book.id == currentBookId ? const Icon(Icons.check, color: AppTheme.primaryGold) : null,
              onTap: () {
                ref.read(currentBookIdProvider.notifier).setCurrentBook(book.id!);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已切换到「${book.name}」')));
              },
            )),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add, color: AppTheme.primaryGold),
              title: const Text('管理账本'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const BookManagePage())).then((_) => _loadBooks());
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final currentBookId = ref.watch(currentBookIdProvider);
    final currentBook = _books.firstWhere((b) => b.id == currentBookId, orElse: () => Book(name: '默认账本', createdAt: ''));
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        color: AppTheme.primaryGold,
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
      ),
      child: Row(
        children: [
          const Icon(Icons.book, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(currentBook.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
          const Spacer(),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '本月', label: Text('本月')),
              ButtonSegment(value: '本年', label: Text('本年')),
              ButtonSegment(value: '全部', label: Text('全部')),
            ],
            selected: {_timeRange},
            onSelectionChanged: (s) { setState(() => _timeRange = s.first); _loadData(isRefresh: true); },
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? Colors.white : Colors.transparent),
              foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? AppTheme.primaryGold : Colors.white70),
              side: WidgetStateProperty.all(const BorderSide(color: Colors.white30)),
              textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
              padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    final totalIncome = _incomeStats['totalAmount'] ?? 0;
    final totalCost = _incomeStats['totalCost'] ?? 0;
    final totalExpense = _expenseStats['totalAmount'] ?? 0;
    final grossProfit = _incomeStats['totalGrossProfit'] ?? 0;
    // 纯利润与收入侧价税分离口径保持一致：一般纳税人专票进项税可抵扣、不重复计入费用；
    // 小规模纳税人进项不可抵扣，支出全额计入费用。
    final taxpayerType = ref.watch(taxpayerTypeProvider);
    final deductibleTax = taxpayerType == 'small'
        ? 0.0
        : (_expenseStats['deductibleTax'] ?? 0);
    final netProfit = grossProfit - (totalExpense - deductibleTax);
    final netCash = (_incomeStats['paidAmount'] ?? 0) - (_expenseStats['paidAmount'] ?? 0);

    final cards = [
      {'label': '总收入', 'value': totalIncome, 'color': AppTheme.incomeGreen, 'icon': Icons.arrow_downward},
      {'label': '总成本', 'value': totalCost, 'color': AppTheme.warningOrange, 'icon': Icons.shopping_bag},
      {'label': '总支出', 'value': totalExpense, 'color': AppTheme.expenseRed, 'icon': Icons.arrow_upward},
      {'label': '总利润', 'value': grossProfit, 'color': AppTheme.primaryGold, 'icon': Icons.trending_up},
      {'label': '纯利润', 'value': netProfit, 'color': AppTheme.infoBlue, 'icon': Icons.account_balance_wallet},
      {'label': '净现金', 'value': netCash, 'color': Colors.teal, 'icon': Icons.savings},
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: cards.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 1.1, crossAxisSpacing: 8, mainAxisSpacing: 8),
        itemBuilder: (context, index) {
          final c = cards[index];
          final value = (c['value'] as num).toDouble();
          return GestureDetector(
            onTap: () => AmountUtils.showFullAmountDialog(context, c['label'] as String, value),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _isDark ? AppTheme.darkCard : Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(_isDark ? 0.25 : 0.05), blurRadius: 4, offset: const Offset(0, 2))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Row(children: [Icon(c['icon'] as IconData, size: 16, color: c['color'] as Color), const SizedBox(width: 4), Expanded(child: Text(c['label'] as String, style: TextStyle(fontSize: 11, color: _isDark ? AppTheme.darkText : AppTheme.textSecondary), overflow: TextOverflow.ellipsis))]),
                Text(_fmtShort(value, _amountMode), style: TextStyle(fontSize: _amountMode == 'full' ? 13 : 15, fontWeight: FontWeight.bold, color: c['color'] as Color), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPaymentStatus() {
    final paid = _incomeStats['paidAmount'] ?? 0;
    final unpaid = _incomeStats['unpaidAmount'] ?? 0;
    final unpaidExpense = _expenseStats['unpaidAmount'] ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        Expanded(child: GestureDetector(onTap: () => AmountUtils.showFullAmountDialog(context, '已收款', paid), child: _statusCard('已收款', _fmtShort(paid, _amountMode), AppTheme.incomeGreen, Icons.check_circle))),
        const SizedBox(width: 8),
        Expanded(child: GestureDetector(onTap: () => AmountUtils.showFullAmountDialog(context, '未收款', unpaid), child: _statusCard('未收款', _fmtShort(unpaid, _amountMode), AppTheme.warningOrange, Icons.pending))),
        const SizedBox(width: 8),
        Expanded(child: GestureDetector(onTap: () => AmountUtils.showFullAmountDialog(context, '未付款', unpaidExpense), child: _statusCard('未付款', _fmtShort(unpaidExpense, _amountMode), AppTheme.expenseRed, Icons.error_outline))),
      ]),
    );
  }

  Widget _statusCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: _isDark ? AppTheme.darkCard : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.2))),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 14, color: color), const SizedBox(width: 4), Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500))]),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  Widget _buildChart() {
    if (_monthlyTrend.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Card(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: Column(children: [Icon(Icons.show_chart, size: 48, color: AppTheme.primaryGold.withOpacity(0.3)), const SizedBox(height: 8), const Text('暂无数据，记一笔后显示趋势图', style: TextStyle(color: AppTheme.textHint))])))),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('近12个月收支趋势', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: _maxY(),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => Colors.black87,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final month = '${_monthlyTrend[group.x]['month']}';
                        final income = (_monthlyTrend[group.x]['income'] as num).toDouble();
                        final expense = (_monthlyTrend[group.x]['expense'] as num).toDouble();
                        return BarTooltipItem(
                          '$month\n收入:¥${_group2(income.toStringAsFixed(2))}\n支出:¥${_group2(expense.toStringAsFixed(2))}',
                          const TextStyle(color: Colors.white, fontSize: 11),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, interval: 1, getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx >= 0 && idx < _monthlyTrend.length) {
                        final m = _monthlyTrend[idx]['month'] as String;
                        return Padding(padding: const EdgeInsets.only(top: 4), child: Text(m.substring(5), style: const TextStyle(fontSize: 10, color: AppTheme.textHint)));
                      }
                      return const SizedBox.shrink();
                    })),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  barGroups: _monthlyTrend.asMap().entries.map((e) {
                    final i = e.key;
                    final income = (e.value['income'] as num).toDouble();
                    final expense = (e.value['expense'] as num).toDouble();
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(toY: income, color: AppTheme.incomeGreen, width: 10, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
                        BarChartRodData(toY: expense, color: AppTheme.expenseRed, width: 10, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
                      ],
                    );
                  }).toList(),
                ),
                // 关闭fl_chart数据切换动画：每次刷新/记账后不再重播"柱子生长"动画，杜绝高频操作下图表闪烁、滑动抖动
                swapAnimationDuration: Duration.zero,
              ),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _legendItem(AppTheme.incomeGreen, '收入'),
              const SizedBox(width: 24),
              _legendItem(AppTheme.expenseRed, '支出'),
            ]),
          ]),
        ),
      ),
    );
  }

  double _maxY() {
    double max = 0;
    for (var m in _monthlyTrend) {
      final income = (m['income'] as num).toDouble();
      final expense = (m['expense'] as num).toDouble();
      max = [max, income, expense].reduce((a, b) => a > b ? a : b);
    }
    // 全部为0时给非0上限，避免 fl_chart 坐标轴/动画异常
    return max <= 0 ? 1.0 : max * 1.2;
  }

  Widget _legendItem(Color color, String label) {
    return Row(children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))), const SizedBox(width: 6), Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))]);
  }

  Widget _buildRecentSummary() {
    final totalIncome = _incomeStats['totalAmount'] ?? 0;
    final totalExpense = _expenseStats['totalAmount'] ?? 0;
    final totalTax = (_incomeStats['totalTax'] ?? 0) + (_expenseStats['totalTax'] ?? 0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('本期汇总', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _summaryRow('收入总额（价税合计）', _fmt(totalIncome), AppTheme.incomeGreen),
            _summaryRow('支出总额', _fmt(totalExpense), AppTheme.expenseRed),
            _summaryRow('税额合计', _fmt(totalTax), AppTheme.warningOrange),
            const Divider(height: 16),
            _summaryRow('本期结余', _fmt(totalIncome - totalExpense), (totalIncome - totalExpense) >= 0 ? AppTheme.incomeGreen : AppTheme.expenseRed, bold: true),
          ]),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, Color color, {bool bold = false}) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)), Text(value, style: TextStyle(fontSize: 14, color: color, fontWeight: bold ? FontWeight.bold : FontWeight.normal))]));
  }
}
