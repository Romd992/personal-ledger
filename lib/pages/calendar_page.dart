import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../models/income.dart';
import '../models/expense.dart';
import 'income_form_page.dart';
import 'expense_form_page.dart';

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime? _selectedDate;
  Map<String, Map<String, double>> _dailyData = {}; // 'YYYY-MM-DD' -> {'income': x, 'expense': y}
  List<Income> _dayIncomes = [];
  List<Expense> _dayExpenses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _loadMonthData();
  }

  Future<void> _loadMonthData() async {
    setState(() => _loading = true);
    final year = _currentMonth.year;
    final month = _currentMonth.month;
    final startDate = '$year-${month.toString().padLeft(2,'0')}-01';
    final lastDay = DateTime(year, month + 1, 0).day;
    final endDate = '$year-${month.toString().padLeft(2,'0')}-${lastDay.toString().padLeft(2,'0')}';

    final incomes = await DatabaseService.instance.getIncomes(startDate: startDate, endDate: endDate);
    final expenses = await DatabaseService.instance.getExpenses(startDate: startDate, endDate: endDate);

    final Map<String, Map<String, double>> data = {};
    for (var inc in incomes) {
      data.putIfAbsent(inc.date, () => {'income': 0, 'expense': 0});
      data[inc.date]!['income'] = (data[inc.date]!['income'] ?? 0) + inc.amount;
    }
    for (var exp in expenses) {
      data.putIfAbsent(exp.date, () => {'income': 0, 'expense': 0});
      data[exp.date]!['expense'] = (data[exp.date]!['expense'] ?? 0) + exp.amount;
    }

    if (mounted) {
      setState(() {
        _dailyData = data;
        _loading = false;
      });
      _loadDayData();
    }
  }

  Future<void> _loadDayData() async {
    if (_selectedDate == null) return;
    final dateStr = '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2,'0')}-${_selectedDate!.day.toString().padLeft(2,'0')}';
    final incomes = await DatabaseService.instance.getIncomes(startDate: dateStr, endDate: dateStr);
    final expenses = await DatabaseService.instance.getExpenses(startDate: dateStr, endDate: dateStr);
    if (mounted) {
      setState(() {
        _dayIncomes = incomes;
        _dayExpenses = expenses;
      });
    }
  }

  void _previousMonth() {
    setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1));
    _loadMonthData();
  }

  void _nextMonth() {
    setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1));
    _loadMonthData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日历视图'),
        actions: [
          IconButton(icon: const Icon(Icons.today), onPressed: () { setState(() { _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1); _selectedDate = DateTime.now(); }); _loadMonthData(); }),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              _buildCalendarHeader(),
              _buildWeekdayHeader(),
              _buildCalendarGrid(),
              _buildDaySummary(),
              Expanded(child: _buildDayDetail()),
            ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(),
        icon: const Icon(Icons.add),
        label: const Text('记一笔'),
        backgroundColor: AppTheme.primaryGold,
      ),
    );
  }

  Widget _buildCalendarHeader() {
    final monthIncome = _dailyData.values.fold<double>(0, (s, d) => s + (d['income'] ?? 0));
    final monthExpense = _dailyData.values.fold<double>(0, (s, d) => s + (d['expense'] ?? 0));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(color: AppTheme.primaryGold, borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16))),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton(icon: const Icon(Icons.chevron_left, color: Colors.white), onPressed: _previousMonth),
          GestureDetector(
            onTap: _showYearPicker,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${_currentMonth.year}年${_currentMonth.month}月', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.chevron_right, color: Colors.white), onPressed: _nextMonth),
        ]),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _headerStat('收入', monthIncome, Colors.white),
          Container(width: 1, height: 24, color: Colors.white30),
          _headerStat('支出', monthExpense, Colors.white),
          Container(width: 1, height: 24, color: Colors.white30),
          _headerStat('结余', monthIncome - monthExpense, Colors.white),
        ]),
      ]),
    );
  }

  /// 显示年份选择器
  void _showYearPicker() {
    final currentYear = _currentMonth.year;
    final startYear = 2000;
    final endYear = 2300;
    final years = List<int>.generate(endYear - startYear + 1, (i) => startYear + i);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        height: 300,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('选择年份', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: 2),
                itemCount: years.length,
                itemBuilder: (_, i) {
                  final year = years[i];
                  final isSelected = year == currentYear;
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _currentMonth = DateTime(year, _currentMonth.month, 1));
                      _loadMonthData();
                    },
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primaryGold : Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '$year年',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerStat(String label, double value, Color color) {
    return Column(children: [Text(label, style: TextStyle(fontSize: 11, color: color.withOpacity(0.8))), Text('¥${value.toStringAsFixed(2)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color))]);
  }

  Widget _buildWeekdayHeader() {
    const weekdays = ['日', '一', '二', '三', '四', '五', '六'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(children: weekdays.map((d) => Expanded(child: Center(child: Text(d, style: TextStyle(fontSize: 12, color: d == '日' || d == '六' ? AppTheme.expenseRed : AppTheme.textSecondary, fontWeight: FontWeight.w500))))).toList()),
    );
  }

  Widget _buildCalendarGrid() {
    final year = _currentMonth.year;
    final month = _currentMonth.month;
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0).day;
    final firstWeekday = firstDay.weekday % 7; // 0=Sunday

    final List<Widget> cells = [];
    // 空白格
    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const Expanded(child: SizedBox()));
    }
    // 日期格
    for (int day = 1; day <= lastDay; day++) {
      final date = DateTime(year, month, day);
      final dateStr = '$year-${month.toString().padLeft(2,'0')}-${day.toString().padLeft(2,'0')}';
      final hasData = _dailyData.containsKey(dateStr);
      final isSelected = _selectedDate != null && _selectedDate!.year == year && _selectedDate!.month == month && _selectedDate!.day == day;
      final isToday = date.year == DateTime.now().year && date.month == DateTime.now().month && date.day == DateTime.now().day;
      final isWeekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

      cells.add(Expanded(child: GestureDetector(
        onTap: () => setState(() { _selectedDate = date; _loadDayData(); }),
        child: Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryGold : isToday ? AppTheme.primaryGold.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: [
            Text('$day', style: TextStyle(fontSize: 14, fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.white : isWeekend ? AppTheme.expenseRed : AppTheme.textPrimary)),
            const SizedBox(height: 2),
            if (hasData) Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if ((_dailyData[dateStr]!['income'] ?? 0) > 0) Container(width: 5, height: 5, decoration: const BoxDecoration(color: AppTheme.incomeGreen, shape: BoxShape.circle)),
              const SizedBox(width: 2),
              if ((_dailyData[dateStr]!['expense'] ?? 0) > 0) Container(width: 5, height: 5, decoration: const BoxDecoration(color: AppTheme.expenseRed, shape: BoxShape.circle)),
            ]) else const SizedBox(height: 5),
          ]),
        ),
      )));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(children: [
        for (int row = 0; row < (cells.length / 7).ceil(); row++)
          Row(children: cells.skip(row * 7).take(7).toList()),
      ]),
    );
  }

  Widget _buildDaySummary() {
    if (_selectedDate == null) return const SizedBox.shrink();
    final dayIncome = _dayIncomes.fold<double>(0, (s, i) => s + i.amount);
    final dayExpense = _dayExpenses.fold<double>(0, (s, e) => s + e.amount);
    final dateStr = '${_selectedDate!.year}年${_selectedDate!.month}月${_selectedDate!.day}日';
    final weekday = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][_selectedDate!.weekday % 7];

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))]),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(dateStr, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          Text(weekday, style: const TextStyle(fontSize: 11, color: AppTheme.textHint)),
        ])),
        _dayStat('收入', dayIncome, AppTheme.incomeGreen),
        const SizedBox(width: 16),
        _dayStat('支出', dayExpense, AppTheme.expenseRed),
        const SizedBox(width: 16),
        _dayStat('结余', dayIncome - dayExpense, (dayIncome - dayExpense) >= 0 ? AppTheme.incomeGreen : AppTheme.expenseRed),
      ]),
    );
  }

  Widget _dayStat(String label, double value, Color color) {
    return Column(children: [Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textHint)), Text('¥${value.toStringAsFixed(2)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color))]);
  }

  Widget _buildDayDetail() {
    if (_selectedDate == null) return const Center(child: Text('请选择日期'));
    if (_dayIncomes.isEmpty && _dayExpenses.isEmpty) {
      return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.event_note, size: 48, color: AppTheme.textHint), SizedBox(height: 8), Text('当天暂无记录', style: TextStyle(color: AppTheme.textHint))]));
    }
    return ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
      if (_dayIncomes.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('收入', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.incomeGreen))),
        ..._dayIncomes.map((inc) => _buildIncomeItem(inc)),
      ],
      if (_dayExpenses.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('支出', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.expenseRed))),
        ..._dayExpenses.map((exp) => _buildExpenseItem(exp)),
      ],
      const SizedBox(height: 80),
    ]);
  }

  Widget _buildIncomeItem(Income inc) {
    return Card(margin: const EdgeInsets.symmetric(vertical: 3), child: ListTile(
      dense: true,
      leading: const CircleAvatar(radius: 16, backgroundColor: AppTheme.incomeGreen, child: Icon(Icons.arrow_downward, size: 16, color: Colors.white)),
      title: Text(inc.customerName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(inc.productName ?? '', style: const TextStyle(fontSize: 11, color: AppTheme.textHint), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text('+¥${inc.amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.incomeGreen)),
      onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => IncomeFormPage(existingIncome: inc))); _loadMonthData(); },
    ));
  }

  Widget _buildExpenseItem(Expense exp) {
    return Card(margin: const EdgeInsets.symmetric(vertical: 3), child: ListTile(
      dense: true,
      leading: const CircleAvatar(radius: 16, backgroundColor: AppTheme.expenseRed, child: Icon(Icons.arrow_upward, size: 16, color: Colors.white)),
      title: Text(exp.expenseTypeName ?? '支出', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(exp.supplierNote ?? '', style: const TextStyle(fontSize: 11, color: AppTheme.textHint), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text('-¥${exp.amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.expenseRed)),
      onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => ExpenseFormPage(existingExpense: exp))); _loadMonthData(); },
    ));
  }

  void _showAddSheet() {
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (ctx) => SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('记一笔', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: ElevatedButton.icon(onPressed: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => const IncomeFormPage())).then((_) => _loadMonthData()); }, icon: const Icon(Icons.arrow_downward), label: const Text('记收入'), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.incomeGreen))),
        const SizedBox(width: 12),
        Expanded(child: ElevatedButton.icon(onPressed: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseFormPage())).then((_) => _loadMonthData()); }, icon: const Icon(Icons.arrow_upward), label: const Text('记支出'), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.expenseRed))),
      ]),
    ]))));
  }
}
