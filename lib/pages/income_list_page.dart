import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/income.dart';
import '../providers/data_providers.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import 'income_form_page.dart';

class IncomeListPage extends ConsumerStatefulWidget {
  const IncomeListPage({super.key});

  @override
  ConsumerState<IncomeListPage> createState() => _IncomeListPageState();
}

class _IncomeListPageState extends ConsumerState<IncomeListPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce; // 搜索防抖：停顿300ms才查库，避免每敲一字就查库+整列表闪转圈
  String _paymentFilter = 'all'; // all/paid/unpaid
  String _invoiceFilter = 'all'; // all/none/general/special
  DateTime? _dateFilterStart;
  DateTime? _dateFilterEnd;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incomesAsync = ref.watch(incomesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('收入明细'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.date_range,
              color: (_dateFilterStart != null || _dateFilterEnd != null) ? AppTheme.primaryGold : null,
            ),
            tooltip: '按日期筛选',
            onPressed: _showDateRangePicker,
          ),
          if (_dateFilterStart != null || _dateFilterEnd != null)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: '清除日期筛选',
              onPressed: () {
                setState(() {
                  _dateFilterStart = null;
                  _dateFilterEnd = null;
                });
                _applyFilter();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索客户/商品/备注',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchController.clear(); _applyFilter(); })
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          // 筛选标签 + 更多按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                _filterChip('全部', _paymentFilter == 'all', () => _setPaymentFilter('all')),
                const SizedBox(width: 8),
                _filterChip('已收款', _paymentFilter == 'paid', () => _setPaymentFilter('paid')),
                const SizedBox(width: 8),
                _filterChip('未收款', _paymentFilter == 'unpaid', () => _setPaymentFilter('unpaid')),
                const Spacer(),
                // 更多筛选按钮
                InkWell(
                  onTap: _showFilterDialog,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _invoiceFilter != 'all' ? AppTheme.primaryGold.withOpacity(0.1) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _invoiceFilter != 'all' ? AppTheme.primaryGold : AppTheme.divider),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tune, size: 14, color: _invoiceFilter != 'all' ? AppTheme.primaryGold : AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          _invoiceFilter != 'all' ? _invoiceFilterLabel : '更多',
                          style: TextStyle(fontSize: 12, color: _invoiceFilter != 'all' ? AppTheme.primaryGold : AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 统计摘要（基于当前筛选/搜索后的列表实时现算，保证与列表完全一致）
          _buildSummary(incomesAsync.valueOrNull ?? const <Income>[]),
          // 列表
          Expanded(
            child: incomesAsync.when(
              data: (incomes) => incomes.isEmpty ? _buildEmpty() : _buildList(incomes),
              loading: () {
                // 搜索/筛选重载时保留上一帧列表，避免"列表→转圈→列表"高频闪烁；仅首次无数据才显示加载圈
                final prev = incomesAsync.valueOrNull;
                if (prev != null && prev.isNotEmpty) return _buildList(prev);
                return const Center(child: CircularProgressIndicator());
              },
              error: (e, _) => Center(child: Text('加载失败: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const IncomeFormPage()));
          if (result == true) ref.invalidate(incomesProvider);
        },
        backgroundColor: AppTheme.incomeGreen,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : AppTheme.textSecondary)),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppTheme.primaryGold,
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? AppTheme.primaryGold : AppTheme.divider),
      visualDensity: VisualDensity.compact,
    );
  }

  String get _invoiceFilterLabel {
    switch (_invoiceFilter) {
      case 'none': return '不开票';
      case 'general': return '普票';
      case 'special': return '专票';
      default: return '更多';
    }
  }

  void _setPaymentFilter(String value) {
    setState(() => _paymentFilter = value);
    _applyFilter();
  }

  void _onSearchChanged(String _) {
    setState(() {}); // 即时刷新搜索框清除按钮的显隐
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), _applyFilter);
  }

  void _applyFilter() {
    ref.read(incomeFilterProvider.notifier).state = IncomeFilter(
      paymentStatus: _paymentFilter == 'all' ? null : _paymentFilter,
      invoiceType: _invoiceFilter == 'all' ? null : _invoiceFilter,
      keyword: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
      startDate: _dateFilterStart != null
          ? '${_dateFilterStart!.year}-${_dateFilterStart!.month.toString().padLeft(2,'0')}-${_dateFilterStart!.day.toString().padLeft(2,'0')}'
          : null,
      endDate: _dateFilterEnd != null
          ? '${_dateFilterEnd!.year}-${_dateFilterEnd!.month.toString().padLeft(2,'0')}-${_dateFilterEnd!.day.toString().padLeft(2,'0')}'
          : null,
    );
  }

  /// 显示日期范围选择器
  void _showDateRangePicker() async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2300),
      initialDateRange: (_dateFilterStart != null && _dateFilterEnd != null)
          ? DateTimeRange(start: _dateFilterStart!, end: _dateFilterEnd!)
          : DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
      helpText: '选择日期范围',
      fieldStartHintText: '开始日期',
      fieldEndHintText: '结束日期',
    );

    if (result != null) {
      setState(() {
        _dateFilterStart = result.start;
        _dateFilterEnd = result.end;
      });
      _applyFilter();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已筛选：${result.start.year}年${result.start.month}月${result.start.day}日 至 ${result.end.year}年${result.end.month}月${result.end.day}日'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('筛选条件', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('发票类型', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              _filterOptionChip('全部', _invoiceFilter == 'all', () {
                setState(() => _invoiceFilter = 'all');
                _applyFilter();
                Navigator.pop(ctx);
              }),
              _filterOptionChip('不开票', _invoiceFilter == 'none', () {
                setState(() => _invoiceFilter = 'none');
                _applyFilter();
                Navigator.pop(ctx);
              }),
              _filterOptionChip('普票', _invoiceFilter == 'general', () {
                setState(() => _invoiceFilter = 'general');
                _applyFilter();
                Navigator.pop(ctx);
              }),
              _filterOptionChip('专票', _invoiceFilter == 'special', () {
                setState(() => _invoiceFilter = 'special');
                _applyFilter();
                Navigator.pop(ctx);
              }),
            ]),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _filterOptionChip(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 13, color: selected ? Colors.white : AppTheme.textSecondary)),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppTheme.primaryGold,
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? AppTheme.primaryGold : AppTheme.divider),
      showCheckmark: true,
      checkmarkColor: Colors.white,
    );
  }

  Widget _buildSummary(List<Income> list) {
    // 由当前筛选后的明细现算，避免统计卡与列表口径不一致
    double total = 0, paid = 0, unpaid = 0, gross = 0;
    for (final i in list) {
      total += i.amount;
      gross += i.grossProfit;
      if (i.paymentStatus == 'paid') {
        paid += i.amount;
      } else {
        unpaid += i.amount;
      }
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppTheme.incomeGreen.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.incomeGreen.withOpacity(0.2))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _summaryItem('总收入', '¥${total.toStringAsFixed(2)}', AppTheme.incomeGreen),
        _summaryItem('已收', '¥${paid.toStringAsFixed(2)}', AppTheme.infoBlue),
        _summaryItem('未收', '¥${unpaid.toStringAsFixed(2)}', AppTheme.warningOrange),
        _summaryItem('毛利', '¥${gross.toStringAsFixed(2)}', AppTheme.primaryGold),
      ]),
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    return Column(children: [
      Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
    ]);
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.arrow_downward, size: 64, color: AppTheme.incomeGreen.withOpacity(0.3)),
        const SizedBox(height: 16),
        const Text('暂无收入记录', style: TextStyle(fontSize: 16, color: AppTheme.textHint)),
        const SizedBox(height: 8),
        const Text('点击右下角 + 添加收入', style: TextStyle(fontSize: 13, color: AppTheme.textHint)),
      ]),
    );
  }

  Widget _buildList(List<Income> incomes) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: incomes.length,
      itemBuilder: (context, index) {
        final income = incomes[index];
        return Dismissible(
          key: Key('income_${income.id}'),
          direction: DismissDirection.endToStart,
          background: Container(color: AppTheme.expenseRed, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
          confirmDismiss: (_) async {
            return await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
              title: const Text('确认删除'),
              content: Text('确定删除这条收入记录吗？\n${income.customerName} - ¥${income.amount.toStringAsFixed(2)}'),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: AppTheme.expenseRed)))],
            ));
          },
          onDismissed: (_) async {
            // deleteIncome 内部已统一将原记录写入回收站（保留30天），
            // 此处不再重复 insertRecycleItem，避免删1条产生2份回收站副本、还原后出现重复记录
            await DatabaseService.instance.deleteIncome(income.id!);
            ref.invalidate(incomesProvider);
            ref.invalidate(incomeStatsProvider);
            // 同步递增全局刷新信号，让首页/税务/统计/客户等缓存页面一并刷新
            ref.read(refreshTriggerProvider.notifier).state++;
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已移入回收站，30天内可恢复')));
          },
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: InkWell(
              onTap: () async {
                final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => IncomeFormPage(existingIncome: income)));
                if (result == true) ref.invalidate(incomesProvider);
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(income.customerName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                    // 未收款金额显示橙色，已收款显示绿色
                    Text(
                      '¥${income.amount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: income.paymentStatus == 'paid' ? AppTheme.incomeGreen : AppTheme.warningOrange,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(income.productName, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text(income.date, style: const TextStyle(fontSize: 11, color: AppTheme.textHint)),
                    const SizedBox(width: 10),
                    _statusTag(income.paymentStatus == 'paid' ? '已收款' : '未收款', income.paymentStatus == 'paid' ? AppTheme.incomeGreen : AppTheme.warningOrange),
                    const SizedBox(width: 6),
                    // 普票蓝色，专票紫色，不开票不显示
                    if (income.invoiceType == 'general')
                      _statusTag('普票', Colors.blue),
                    if (income.invoiceType == 'special')
                      _statusTag('专票', Colors.purple),
                    if (income.cost > 0) ...[
                      const SizedBox(width: 6),
                      Text('成本:¥${income.cost.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                      const SizedBox(width: 6),
                      Text('毛利:¥${income.grossProfit.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: AppTheme.primaryGold)),
                    ],
                  ]),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _statusTag(String text, Color color) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(3), border: Border.all(color: color.withOpacity(0.3))), child: Text(text, style: TextStyle(fontSize: 10, color: color)));
  }
}
