import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../models/income.dart';
import '../models/expense.dart';
import '../providers/data_providers.dart';
import '../providers/settings_providers.dart';

class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _timeRange = '本年';
  Map<String, double> _incomeStats = {};
  Map<String, double> _expenseStats = {};
  List<Map<String, dynamic>> _monthlyTrend = [];
  List<Income> _incomes = [];
  List<Expense> _expenses = [];
  bool _loading = true;
  final GlobalKey _repaintKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool isRefresh = false}) async {
    if (!isRefresh) setState(() => _loading = true);
    final now = DateTime.now();
    String? startDate, endDate;
    if (_timeRange == '本月') {
      startDate = '${now.year}-${now.month.toString().padLeft(2,'0')}-01';
      final lastDay = DateTime(now.year, now.month + 1, 0).day;
      endDate = '${now.year}-${now.month.toString().padLeft(2,'0')}-${lastDay.toString().padLeft(2,'0')}';
    } else if (_timeRange == '本年') {
      startDate = '${now.year}-01-01';
      endDate = '${now.year}-12-31';
    } else if (_timeRange == '近7天') {
      final start = now.subtract(const Duration(days: 6));
      startDate = '${start.year}-${start.month.toString().padLeft(2,'0')}-${start.day.toString().padLeft(2,'0')}';
      endDate = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
    } else if (_timeRange == '近30天') {
      final start = now.subtract(const Duration(days: 29));
      startDate = '${start.year}-${start.month.toString().padLeft(2,'0')}-${start.day.toString().padLeft(2,'0')}';
      endDate = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
    } else if (_timeRange == '近90天') {
      final start = now.subtract(const Duration(days: 89));
      startDate = '${start.year}-${start.month.toString().padLeft(2,'0')}-${start.day.toString().padLeft(2,'0')}';
      endDate = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
    } else if (_timeRange.startsWith('自定义:')) {
      // 自定义范围格式：自定义:2024-01-01~2024-12-31
      final range = _timeRange.substring(3);
      final parts = range.split('~');
      if (parts.length == 2) {
        startDate = parts[0];
        endDate = parts[1];
      }
    }

    final income = await DatabaseService.instance.getIncomeStats(startDate: startDate, endDate: endDate);
    final expense = await DatabaseService.instance.getExpenseStats(startDate: startDate, endDate: endDate);
    final trend = await DatabaseService.instance.getMonthlyTrend(months: 12);
    final incomes = await DatabaseService.instance.getIncomes(startDate: startDate, endDate: endDate);
    final expenses = await DatabaseService.instance.getExpenses(startDate: startDate, endDate: endDate);

    if (mounted) {
      setState(() {
        _incomeStats = income;
        _expenseStats = expense;
        _monthlyTrend = trend;
        _incomes = incomes;
        _expenses = expenses;
        _loading = false;
      });
    }
  }

  /// 显示自定义日期范围选择器
  Future<void> _showCustomDateRange() async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2300),
      initialDateRange: DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
      helpText: '选择统计日期范围',
      fieldStartHintText: '开始日期',
      fieldEndHintText: '结束日期',
    );

    if (result != null) {
      final startStr = '${result.start.year}-${result.start.month.toString().padLeft(2,'0')}-${result.start.day.toString().padLeft(2,'0')}';
      final endStr = '${result.end.year}-${result.end.month.toString().padLeft(2,'0')}-${result.end.day.toString().padLeft(2,'0')}';
      setState(() => _timeRange = '自定义:$startStr~$endStr');
      _loadData(isRefresh: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已筛选：$startStr 至 $endStr')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 记账/删改后全局刷新信号触发：静默刷新，修复底部导航缓存导致统计图表停留"暂无数据"的问题
    ref.listen(refreshTriggerProvider, (previous, next) {
      if (previous != next) _loadData(isRefresh: true);
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('统计分析'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [Tab(text: '收支趋势'), Tab(text: '利润税务'), Tab(text: '收入构成'), Tab(text: '支出构成')],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.image_outlined), tooltip: '导出当前图表为图片', onPressed: _exportChartImage),
          PopupMenuButton<String>(
            icon: const Icon(Icons.date_range),
            onSelected: (v) async {
              if (v == 'custom') {
                await _showCustomDateRange();
              } else {
                setState(() => _timeRange = v);
                _loadData(isRefresh: true);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: '本月', child: Text('本月')),
              PopupMenuItem(value: '本年', child: Text('本年')),
              PopupMenuItem(value: '全部', child: Text('全部')),
              PopupMenuItem(value: '近7天', child: Text('近7天')),
              PopupMenuItem(value: '近30天', child: Text('近30天')),
              PopupMenuItem(value: '近90天', child: Text('近90天')),
              PopupMenuItem(value: 'custom', child: Text('自定义日期范围...')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RepaintBoundary(
              key: _repaintKey,
              child: Container(
                color: AppTheme.bgWarm,
                child: TabBarView(
                  controller: _tabController,
                  children: [_buildTrendTab(), _buildProfitTaxTab(), _buildIncomeCompositionTab(), _buildExpenseCompositionTab()],
                ),
              ),
            ),
    );
  }

  Widget _buildTrendTab() {
    if (_monthlyTrend.isEmpty) return _emptyChart();
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('近12个月收支趋势', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        SizedBox(height: 250, child: _buildBarChart()),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [_legend(AppTheme.incomeGreen, '收入'), const SizedBox(width: 24), _legend(AppTheme.expenseRed, '支出')]),
        const SizedBox(height: 24),
        _buildTrendTable(),
      ]),
    );
  }

  Widget _buildBarChart() {
    double maxY = 0;
    for (var m in _monthlyTrend) {
      final income = (m['income'] as num).toDouble();
      final expense = (m['expense'] as num).toDouble();
      maxY = [maxY, income, expense].reduce((a, b) => a > b ? a : b);
    }
    maxY = maxY <= 0 ? 1.0 : maxY * 1.2;

    final groups = _monthlyTrend.asMap().entries.map((e) {
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(toY: (e.value['income'] as num).toDouble(), color: AppTheme.incomeGreen, width: 10, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
          BarChartRodData(toY: (e.value['expense'] as num).toDouble(), color: AppTheme.expenseRed, width: 10, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
        ],
      );
    }).toList();

    return BarChart(BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: maxY,
      barTouchData: BarTouchData(enabled: true),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, getTitlesWidget: (v, _) {
          final idx = v.toInt();
          if (idx >= 0 && idx < _monthlyTrend.length) {
            return Padding(padding: const EdgeInsets.only(top: 4), child: Text('${_monthlyTrend[idx]['month']}'.substring(5), style: const TextStyle(fontSize: 10, color: AppTheme.textHint)));
          }
          return const SizedBox.shrink();
        })),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      barGroups: groups,
      ),
      swapAnimationDuration: Duration.zero,
    );
  }

  Widget _buildTrendTable() {
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
      const Row(children: [Expanded(child: Text('月份', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))), Expanded(child: Text('收入', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.right)), Expanded(child: Text('支出', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.right)), Expanded(child: Text('结余', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.right))]),
      const Divider(),
      ..._monthlyTrend.reversed.map((m) {
        final income = (m['income'] as num).toDouble();
        final expense = (m['expense'] as num).toDouble();
        final balance = income - expense;
        return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
          Expanded(child: Text('${m['month']}', style: const TextStyle(fontSize: 12))),
          Expanded(child: Text('¥${income.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: AppTheme.incomeGreen), textAlign: TextAlign.right)),
          Expanded(child: Text('¥${expense.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: AppTheme.expenseRed), textAlign: TextAlign.right)),
          Expanded(child: Text('¥${balance.toStringAsFixed(2)}', style: TextStyle(fontSize: 12, color: balance >= 0 ? AppTheme.incomeGreen : AppTheme.expenseRed, fontWeight: FontWeight.w500), textAlign: TextAlign.right)),
        ]));
      }),
    ])));
  }

  Widget _buildProfitTaxTab() {
    final totalIncome = _incomeStats['totalExcludingTax'] ?? 0;
    final totalCost = _incomeStats['totalCost'] ?? 0;
    final totalExpense = _expenseStats['totalAmount'] ?? 0;
    final grossProfit = _incomeStats['totalGrossProfit'] ?? 0;
    // 与首页一致：一般纳税人专票进项税可抵扣、不重复计入费用；小规模不可抵扣
    final deductible = ref.watch(taxpayerTypeProvider) == 'small' ? 0.0 : (_expenseStats['deductibleTax'] ?? 0);
    final netProfit = grossProfit - (totalExpense - deductible);
    final incomeTax = _incomeStats['totalTax'] ?? 0;
    final expenseTax = _expenseStats['totalTax'] ?? 0;

    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('利润统计', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      _statCard('总收入（不含税）', totalIncome, AppTheme.incomeGreen),
      _statCard('总成本', totalCost, AppTheme.warningOrange),
      _statCard('总支出', totalExpense, AppTheme.expenseRed),
      _statCard('毛利润（收入-成本）', grossProfit, AppTheme.primaryGold),
      _statCard('净利润（毛利-支出）', netProfit, netProfit >= 0 ? AppTheme.incomeGreen : AppTheme.expenseRed, bold: true),
      const SizedBox(height: 24),
      const Text('税务统计', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      _statCard('销项税额（收入开票）', incomeTax, AppTheme.warningOrange),
      _statCard('进项税额（支出开票）', expenseTax, AppTheme.infoBlue),
      _statCard('应交增值税（销项-进项）', incomeTax - expenseTax, AppTheme.expenseRed, bold: true),
      const SizedBox(height: 24),
      SizedBox(height: 200, child: _buildProfitChart()),
    ]);
  }

  Widget _buildProfitChart() {
    final data = [
      {'label': '收入', 'value': (_incomeStats['totalExcludingTax'] ?? 0.0).toDouble(), 'color': AppTheme.incomeGreen},
      {'label': '成本', 'value': (_incomeStats['totalCost'] ?? 0.0).toDouble(), 'color': AppTheme.warningOrange},
      {'label': '支出', 'value': (_expenseStats['totalAmount'] ?? 0.0).toDouble(), 'color': AppTheme.expenseRed},
      {'label': '净利', 'value': ((_incomeStats['totalGrossProfit'] ?? 0.0) - ((_expenseStats['totalAmount'] ?? 0.0) - (ref.watch(taxpayerTypeProvider) == 'small' ? 0.0 : (_expenseStats['deductibleTax'] ?? 0.0)))).toDouble(), 'color': AppTheme.primaryGold},
    ];
    final rawMax = data.map((e) => (e['value'] as num).toDouble()).reduce((a, b) => a > b ? a : b);
    final maxV = rawMax <= 0 ? 1.0 : rawMax * 1.2;

    final profitGroups = data.asMap().entries.map((e) {
      return BarChartGroupData(
        x: e.key,
        barRods: [BarChartRodData(toY: (e.value['value'] as num).toDouble(), color: e.value['color'] as Color, width: 30, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))],
      );
    }).toList();

    return BarChart(BarChartData(
      alignment: BarChartAlignment.spaceEvenly,
      maxY: maxV,
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (v, _) {
          final idx = v.toInt();
          return idx >= 0 && idx < data.length ? Text(data[idx]['label'] as String, style: const TextStyle(fontSize: 11)) : const SizedBox.shrink();
        })),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      barGroups: profitGroups,
      ),
      swapAnimationDuration: Duration.zero,
    );
  }

  Widget _buildIncomeCompositionTab() {
    if (_incomes.isEmpty) return _emptyChart();
    // 按客户汇总
    final Map<String, double> byCustomer = {};
    for (var inc in _incomes) {
      byCustomer[inc.customerName] = (byCustomer[inc.customerName] ?? 0) + inc.amount;
    }
    final sorted = byCustomer.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = sorted.fold<double>(0, (sum, e) => sum + e.value);

    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('收入构成（按客户，共${sorted.length}个客户）', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      ...sorted.take(10).map((e) {
        final pct = total > 0 ? (e.value / total * 100) : 0;
        return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(e.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))), Text('¥${e.value.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, color: AppTheme.incomeGreen, fontWeight: FontWeight.bold)), const SizedBox(width: 8), Text('${pct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, color: AppTheme.textHint))]),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: pct / 100, backgroundColor: AppTheme.divider, valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.incomeGreen), minHeight: 6, borderRadius: BorderRadius.circular(3)),
        ]));
      }),
    ]);
  }

  Widget _buildExpenseCompositionTab() {
    if (_expenses.isEmpty) return _emptyChart();
    // 按支出类型汇总
    final Map<String, double> byType = {};
    for (var exp in _expenses) {
      final type = exp.expenseTypeName ?? '其他';
      byType[type] = (byType[type] ?? 0) + exp.amount;
    }
    final sorted = byType.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = sorted.fold<double>(0, (sum, e) => sum + e.value);
    final colors = [AppTheme.expenseRed, AppTheme.warningOrange, AppTheme.infoBlue, AppTheme.primaryGold, AppTheme.incomeGreen, Colors.purple, Colors.teal, Colors.pink];

    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('支出构成（按类型，共${sorted.length}种）', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      ...sorted.asMap().entries.map((e) {
        final pct = total > 0 ? (e.value.value / total * 100) : 0;
        final color = colors[e.key % colors.length];
        return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(e.value.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))), Text('¥${e.value.value.toStringAsFixed(2)}', style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.bold)), const SizedBox(width: 8), Text('${pct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, color: AppTheme.textHint))]),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: pct / 100, backgroundColor: AppTheme.divider, valueColor: AlwaysStoppedAnimation<Color>(color), minHeight: 6, borderRadius: BorderRadius.circular(3)),
        ]));
      }),
    ]);
  }

  Widget _statCard(String label, double value, Color color, {bool bold = false}) {
    return Card(margin: const EdgeInsets.symmetric(vertical: 4), child: Padding(padding: const EdgeInsets.all(14), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)), Text('¥${value.toStringAsFixed(2)}', style: TextStyle(fontSize: 16, color: color, fontWeight: bold ? FontWeight.bold : FontWeight.normal))])));
  }

  Widget _legend(Color color, String label) => Row(children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))), const SizedBox(width: 6), Text(label, style: const TextStyle(fontSize: 12))]);

  Widget _emptyChart() => const Center(child: Padding(padding: EdgeInsets.all(48), child: Column(children: [Icon(Icons.bar_chart, size: 64, color: AppTheme.textHint), SizedBox(height: 12), Text('暂无数据', style: TextStyle(fontSize: 16, color: AppTheme.textHint))])));

  /// 导出当前统计页（当前tab）为PNG图片，通过系统分享保存/发送
  Future<void> _exportChartImage() async {
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('截图失败，请稍候重试')));
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw '图片数据为空';
      final bytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      const tabNames = ['收支趋势', '利润税务', '收入构成', '支出构成'];
      final tabName = _tabController.index >= 0 && _tabController.index < tabNames.length ? tabNames[_tabController.index] : '统计';
      final ts = DateTime.now().toString().substring(0, 19).replaceAll(RegExp(r'[: ]'), '_');
      final fileName = '统计图表_${tabName}_$ts.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path, name: fileName)], text: '简帐-统计图表（$tabName）');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出图片失败: $e'), backgroundColor: AppTheme.expenseRed));
    }
  }
}
