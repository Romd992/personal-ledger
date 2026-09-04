import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/expense.dart';
import '../providers/data_providers.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
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
        // 移除右上角筛选按钮，筛选移到列表顶部
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
    );
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppTheme.expenseRed.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.expenseRed.withOpacity(0.2))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _summaryItem('总支出', '¥${total.toStringAsFixed(2)}', AppTheme.expenseRed),
        _summaryItem('已付', '¥${paid.toStringAsFixed(2)}', AppTheme.incomeGreen),
        _summaryItem('未付', '¥${unpaid.toStringAsFixed(2)}', AppTheme.expenseRed),
        _summaryItem('进项税', '¥${tax.toStringAsFixed(2)}', AppTheme.primaryGold),
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
