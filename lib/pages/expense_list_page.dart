import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/expense.dart';
import '../providers/data_providers.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import '../utils/amount_utils.dart';
import '../providers/settings_providers.dart';
import 'expense_form_page.dart';

class ExpenseListPage extends ConsumerStatefulWidget {
  const ExpenseListPage({super.key});

  @override
  ConsumerState<ExpenseListPage> createState() => _ExpenseListPageState();
}

class _ExpenseListPageState extends ConsumerState<ExpenseListPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce; // 搜索防抖：停顿300ms才查库，避免每敲一字就查库+整列表闪转圈
  String _paymentFilter = 'all';
  int? _expenseTypeFilter; // 支出类型筛选
  String? _expenseTypeFilterName;
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
    final incomesAsync = ref.watch(expensesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('支出明细'),
        backgroundColor: AppTheme.expenseRed,
        actions: [
          IconButton(
            icon: Icon(
              Icons.date_range,
              color: (_dateFilterStart != null || _dateFilterEnd != null) ? Colors.white : null,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索类型/说明/备注',
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [
              _filterChip('全部', _paymentFilter == 'all', () => _setPaymentFilter('all')),
              const SizedBox(width: 8),
              _filterChip('已付款', _paymentFilter == 'paid', () => _setPaymentFilter('paid')),
              const SizedBox(width: 8),
              _filterChip('未付款', _paymentFilter == 'unpaid', () => _setPaymentFilter('unpaid')),
              const Spacer(),
              // 更多筛选按钮（按支出类型）
              InkWell(
                onTap: _showTypeFilter,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _expenseTypeFilter != null ? AppTheme.expenseRed.withOpacity(0.1) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _expenseTypeFilter != null ? AppTheme.expenseRed : AppTheme.divider),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune, size: 14, color: _expenseTypeFilter != null ? AppTheme.expenseRed : AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        _expenseTypeFilterName ?? '更多',
                        style: TextStyle(fontSize: 12, color: _expenseTypeFilter != null ? AppTheme.expenseRed : AppTheme.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ]),
          ),
          _buildSummary(incomesAsync.valueOrNull ?? const <Expense>[]),
          Expanded(
            child: incomesAsync.when(
              data: (expenses) => expenses.isEmpty ? _buildEmpty() : _buildList(expenses),
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
          final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseFormPage()));
          if (result == true) ref.invalidate(expensesProvider);
        },
        backgroundColor: AppTheme.expenseRed,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : AppTheme.textSecondary)),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppTheme.expenseRed,
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? AppTheme.expenseRed : AppTheme.divider),
      visualDensity: VisualDensity.compact,
    );
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
    ref.read(expenseFilterProvider.notifier).state = ExpenseFilter(
      paymentStatus: _paymentFilter == 'all' ? null : _paymentFilter,
      expenseTypeId: _expenseTypeFilter,
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

  void _showTypeFilter() {
    ref.read(expenseTypesProvider).whenData((types) {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('按支出类型筛选', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                _filterOptionChip('全部类型', _expenseTypeFilter == null, () {
                  setState(() {
                    _expenseTypeFilter = null;
                    _expenseTypeFilterName = null;
                  });
                  _applyFilter();
                  Navigator.pop(ctx);
                }),
                ...types.map((t) => _filterOptionChip(t.name, _expenseTypeFilter == t.id, () {
                  setState(() {
                    _expenseTypeFilter = t.id;
                    _expenseTypeFilterName = t.name;
                  });
                  _applyFilter();
                  Navigator.pop(ctx);
                })),
              ]),
            ),
            const SizedBox(height: 24),
          ]),
        ),
      );
    });
  }

  Widget _filterOptionChip(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 13, color: selected ? Colors.white : AppTheme.textSecondary)),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppTheme.expenseRed,
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? AppTheme.expenseRed : AppTheme.divider),
      showCheckmark: true,
      checkmarkColor: Colors.white,
    );
  }

  Widget _buildSummary(List<Expense> list) {
    // 由当前筛选后的明细现算，保证统计卡与列表口径完全一致
    double total = 0, paid = 0, unpaid = 0, tax = 0;
    for (final e in list) {
      total += e.amount;
      tax += e.taxAmount;
      if (e.paymentStatus == 'paid') {
        paid += e.amount;
      } else {
        unpaid += e.amount;
      }
    }
    final amountMode = ref.watch(amountDisplayModeProvider);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.expenseRed.withOpacity(0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.expenseRed.withOpacity(0.2))),
      child: Column(children: [
        Row(children: [
          Expanded(child: _summaryItem('总支出', total, AppTheme.expenseRed, amountMode)),
          Expanded(child: _summaryItem('已付', paid, AppTheme.incomeGreen, amountMode)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _summaryItem('未付', unpaid, AppTheme.expenseRed, amountMode)),
          Expanded(child: _summaryItem('进项税', tax, AppTheme.primaryGold, amountMode)),
        ]),
      ]),
    );
  }

  Widget _summaryItem(String label, double value, Color color, String mode) {
    return GestureDetector(
      onTap: () => AmountUtils.showFullAmountDialog(context, label, value),
      child: Column(children: [
        Text('¥${AmountUtils.format(value, mode)}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
      ]),
    );
  }

  Widget _buildEmpty() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.arrow_upward, size: 64, color: AppTheme.expenseRed.withOpacity(0.3)),
      const SizedBox(height: 16),
      const Text('暂无支出记录', style: TextStyle(fontSize: 16, color: AppTheme.textHint)),
      const SizedBox(height: 8),
      const Text('点击右下角 + 添加支出', style: TextStyle(fontSize: 13, color: AppTheme.textHint)),
    ]));
  }

  Widget _buildList(List<Expense> expenses) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: expenses.length,
      itemBuilder: (context, index) {
        final expense = expenses[index];
        return Dismissible(
          key: Key('expense_${expense.id}'),
          direction: DismissDirection.endToStart,
          background: Container(color: AppTheme.expenseRed, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
          confirmDismiss: (_) async {
            return await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
              title: const Text('确认删除'),
              content: Text('确定删除这条支出记录吗？\n${expense.expenseTypeName ?? '支出'} - ¥${expense.amount.toStringAsFixed(2)}'),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: AppTheme.expenseRed)))],
            ));
          },
          onDismissed: (_) async {
            // deleteExpense 内部已统一将原记录写入回收站（保留30天），
            // 此处不再重复 insertRecycleItem，避免删1条产生2份回收站副本、还原后出现重复记录
            await DatabaseService.instance.deleteExpense(expense.id!);
            ref.invalidate(expensesProvider);
            ref.invalidate(expenseStatsProvider);
            // 同步递增全局刷新信号，让首页/税务/统计等缓存页面一并刷新
            ref.read(refreshTriggerProvider.notifier).state++;
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已移入回收站，30天内可恢复')));
          },
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: InkWell(
              onTap: () async {
                final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => ExpenseFormPage(existingExpense: expense)));
                if (result == true) ref.invalidate(expensesProvider);
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(expense.expenseTypeName ?? '其他支出', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                    // 已付款绿色，未付款红色
                    Text(
                      '¥${expense.amount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: expense.paymentStatus == 'paid' ? AppTheme.incomeGreen : AppTheme.expenseRed,
                      ),
                    ),
                  ]),
                  if (expense.supplierNote != null && expense.supplierNote!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(expense.supplierNote!, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 6),
                  Row(children: [
                    Text(expense.date, style: const TextStyle(fontSize: 11, color: AppTheme.textHint)),
                    const SizedBox(width: 10),
                    // 已付款绿色，未付款红色（统一颜色）
                    _statusTag(
                      expense.paymentStatus == 'paid' ? '已付款' : '未付款',
                      expense.paymentStatus == 'paid' ? AppTheme.incomeGreen : AppTheme.expenseRed,
                    ),
                    // 普票蓝色，专票紫色
                    if (expense.invoiceType == 'general') ...[
                      const SizedBox(width: 6),
                      _statusTag('普票', Colors.blue),
                    ],
                    if (expense.invoiceType == 'special') ...[
                      const SizedBox(width: 6),
                      _statusTag('专票', Colors.purple),
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
