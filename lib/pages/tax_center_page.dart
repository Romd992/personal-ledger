import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../models/income.dart';
import '../models/expense.dart';
import '../providers/data_providers.dart';

class TaxCenterPage extends ConsumerStatefulWidget {
  const TaxCenterPage({super.key});

  @override
  ConsumerState<TaxCenterPage> createState() => _TaxCenterPageState();
}

class _TaxCenterPageState extends ConsumerState<TaxCenterPage> {
  String _timeRange = '本年';
  Map<String, double> _incomeStats = {};
  Map<String, double> _expenseStats = {};
  List<Income> _incomes = [];
  List<Expense> _expenses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
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
    }

    final incomeStats = await DatabaseService.instance.getIncomeStats(startDate: startDate, endDate: endDate);
    final expenseStats = await DatabaseService.instance.getExpenseStats(startDate: startDate, endDate: endDate);
    final incomes = await DatabaseService.instance.getIncomes(startDate: startDate, endDate: endDate);
    final expenses = await DatabaseService.instance.getExpenses(startDate: startDate, endDate: endDate);

    if (mounted) {
      setState(() {
        _incomeStats = incomeStats;
        _expenseStats = expenseStats;
        _incomes = incomes;
        _expenses = expenses;
        _loading = false;
      });
    }
  }

  // 按税率统计销项税
  Map<double, double> get _outputTaxByRate {
    final map = <double, double>{};
    for (var inc in _incomes) {
      if (inc.invoiceType != 'none') {
        map[inc.taxRate] = (map[inc.taxRate] ?? 0) + inc.taxAmount;
      }
    }
    return map;
  }

  // 按税率统计进项税
  Map<double, double> get _inputTaxByRate {
    final map = <double, double>{};
    for (var exp in _expenses) {
      if (exp.invoiceType != 'none') {
        map[exp.taxRate] = (map[exp.taxRate] ?? 0) + exp.taxAmount;
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    // 记账/删改后全局刷新信号触发：静默刷新，修复底部导航缓存导致税务数据停留在0的问题
    ref.listen(refreshTriggerProvider, (previous, next) {
      if (previous != next) _loadData(isRefresh: true);
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('税务中心'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.date_range),
            onSelected: (v) => setState(() { _timeRange = v; _loadData(); }),
            itemBuilder: (_) => const [PopupMenuItem(value: '本月', child: Text('本月')), PopupMenuItem(value: '本年', child: Text('本年')), PopupMenuItem(value: '全部', child: Text('全部'))],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _buildMainTaxCard(),
                  const SizedBox(height: 12),
                  _buildTaxBreakdown(),
                  const SizedBox(height: 12),
                  _buildRateBreakdown(),
                  const SizedBox(height: 12),
                  _buildInvoiceSummary(),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildMainTaxCard() {
    final outputTax = _incomeStats['totalTax'] ?? 0;
    final inputTax = _expenseStats['totalTax'] ?? 0;
    final payableTax = outputTax - inputTax;
    final incomeWithInvoice = _incomes.where((i) => i.invoiceType != 'none').length;
    final expenseWithInvoice = _expenses.where((e) => e.invoiceType != 'none').length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('税务概览', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _taxItem('销项税额', outputTax, AppTheme.warningOrange, '收入开票需缴纳')),
            Container(width: 1, height: 60, color: AppTheme.divider),
            Expanded(child: _taxItem('进项税额', inputTax, AppTheme.infoBlue, '支出开票可抵扣')),
          ]),
          const Divider(height: 24),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: payableTax >= 0 ? AppTheme.expenseRed.withOpacity(0.08) : AppTheme.incomeGreen.withOpacity(0.08), borderRadius: BorderRadius.circular(10)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(payableTax >= 0 ? '应交增值税' : '留抵税额', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Text('销项 - 进项', style: TextStyle(fontSize: 11, color: AppTheme.textHint)),
            ]),
            Text('¥${payableTax.abs().toStringAsFixed(2)}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: payableTax >= 0 ? AppTheme.expenseRed : AppTheme.incomeGreen)),
          ])),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _miniStat('已开票收入', '$incomeWithInvoice笔'),
            _miniStat('已开票支出', '$expenseWithInvoice笔'),
            _miniStat('不开票收入', '${_incomes.where((i) => i.invoiceType == 'none').length}笔'),
          ]),
        ]),
      ),
    );
  }

  Widget _taxItem(String label, double value, Color color, String desc) {
    return Column(children: [
      Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
      const SizedBox(height: 4),
      Text('¥${value.toStringAsFixed(2)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      const SizedBox(height: 2),
      Text(desc, style: TextStyle(fontSize: 10, color: AppTheme.textHint), textAlign: TextAlign.center),
    ]);
  }

  Widget _miniStat(String label, String value) {
    return Column(children: [Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), Text(label, style: TextStyle(fontSize: 11, color: AppTheme.textHint))]);
  }

  Widget _buildTaxBreakdown() {
    final generalIncome = _incomes.where((i) => i.invoiceType == 'general').fold<double>(0, (s, i) => s + i.taxAmount);
    final specialIncome = _incomes.where((i) => i.invoiceType == 'special').fold<double>(0, (s, i) => s + i.taxAmount);
    final generalExpense = _expenses.where((e) => e.invoiceType == 'general').fold<double>(0, (s, e) => s + e.taxAmount);
    final specialExpense = _expenses.where((e) => e.invoiceType == 'special').fold<double>(0, (s, e) => s + e.taxAmount);

    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('发票类型明细', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      _breakdownRow('普票 - 销项', generalIncome, AppTheme.warningOrange),
      _breakdownRow('专票 - 销项', specialIncome, AppTheme.expenseRed),
      const Divider(height: 16),
      _breakdownRow('普票 - 进项', generalExpense, AppTheme.infoBlue),
      _breakdownRow('专票 - 进项', specialExpense, Colors.teal),
    ])));
  }

  Widget _breakdownRow(String label, double value, Color color) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
      Text('¥${value.toStringAsFixed(2)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color)),
    ]));
  }

  Widget _buildRateBreakdown() {
    final outputRates = _outputTaxByRate;
    final inputRates = _inputTaxByRate;
    if (outputRates.isEmpty && inputRates.isEmpty) return const SizedBox.shrink();

    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('税率分布', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      if (outputRates.isNotEmpty) ...[
        const Text('销项税率', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textSecondary)),
        const SizedBox(height: 8),
        ...outputRates.entries.map((e) => _rateRow('${(e.key * 100).toInt()}%', e.value, AppTheme.warningOrange)),
        const SizedBox(height: 12),
      ],
      if (inputRates.isNotEmpty) ...[
        const Text('进项税率', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textSecondary)),
        const SizedBox(height: 8),
        ...inputRates.entries.map((e) => _rateRow('${(e.key * 100).toInt()}%', e.value, AppTheme.infoBlue)),
      ],
    ])));
  }

  Widget _rateRow(String rate, double value, Color color) {
    final total = color == AppTheme.warningOrange ? (_incomeStats['totalTax'] ?? 1) : (_expenseStats['totalTax'] ?? 1);
    final pct = total > 0 ? (value / total * 100) : 0;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Text(rate, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)), const Spacer(), Text('¥${value.toStringAsFixed(2)}', style: TextStyle(fontSize: 13, color: color)), const SizedBox(width: 8), Text('${pct.toStringAsFixed(0)}%', style: TextStyle(fontSize: 11, color: AppTheme.textHint))]),
      const SizedBox(height: 4),
      LinearProgressIndicator(value: pct / 100, backgroundColor: AppTheme.divider, valueColor: AlwaysStoppedAnimation<Color>(color), minHeight: 5, borderRadius: BorderRadius.circular(3)),
    ]));
  }

  Widget _buildInvoiceSummary() {
    final unpaidInvoices = _incomes.where((i) => i.invoiceType != 'none' && i.paymentStatus == 'unpaid').length;
    final unpaidAmount = _incomes.where((i) => i.invoiceType != 'none' && i.paymentStatus == 'unpaid').fold<double>(0, (s, i) => s + i.amount);

    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('开票提醒', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      if (unpaidInvoices > 0)
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppTheme.warningOrange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Row(children: [
          const Icon(Icons.warning_amber, color: AppTheme.warningOrange, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('有 $unpaidInvoices 笔已开票收入未收款，金额 ¥${unpaidAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, color: AppTheme.warningOrange))),
        ]))
      else
        const Row(children: [Icon(Icons.check_circle, color: AppTheme.incomeGreen, size: 20), SizedBox(width: 8), Text('所有已开票收入均已收款', style: TextStyle(fontSize: 13, color: AppTheme.incomeGreen))]),
    ])));
  }
}
