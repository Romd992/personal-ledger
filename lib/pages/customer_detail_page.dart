import 'dart:io';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../models/customer.dart';
import '../models/income.dart';
import '../services/database_service.dart';
import 'income_form_page.dart';

class CustomerDetailPage extends StatefulWidget {
  final Customer customer;
  const CustomerDetailPage({super.key, required this.customer});

  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage> {
  List<Income> _incomes = [];
  Map<String, double> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final incomes = await DatabaseService.instance.getIncomes(customerName: widget.customer.name);
    // 按客户筛选统计
    double totalAmount = 0, totalExcludingTax = 0, totalCost = 0, totalTax = 0, totalProfit = 0, paid = 0, unpaid = 0;
    for (var inc in incomes) {
      totalAmount += inc.amount;
      totalExcludingTax += inc.amountExcludingTax;
      totalCost += inc.cost;
      totalTax += inc.taxAmount;
      totalProfit += inc.grossProfit;
      if (inc.paymentStatus == 'paid') paid += inc.amount; else unpaid += inc.amount;
    }
    if (mounted) {
      setState(() {
        _incomes = incomes;
        _stats = {
          'totalAmount': totalAmount,
          'totalExcludingTax': totalExcludingTax,
          'totalCost': totalCost,
          'totalTax': totalTax,
          'totalProfit': totalProfit,
          'paid': paid,
          'unpaid': unpaid,
        };
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customer.name),
        actions: [
          IconButton(icon: const Icon(Icons.receipt_long_outlined), tooltip: '导出对账单', onPressed: _exportStatement),
          IconButton(icon: const Icon(Icons.add), onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => IncomeFormPage(initialCustomer: widget.customer.name)));
            _loadData();
          }),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                children: [
                  _buildCustomerInfo(),
                  _buildStatsCards(),
                  const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text('交易记录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                  if (_incomes.isEmpty)
                    const Padding(padding: EdgeInsets.all(32), child: Center(child: Column(children: [Icon(Icons.receipt_long, size: 48, color: AppTheme.textHint), SizedBox(height: 8), Text('暂无交易记录', style: TextStyle(color: AppTheme.textHint))]))),
                  ..._incomes.map((inc) => _buildIncomeItem(inc)),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildCustomerInfo() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 24, backgroundColor: AppTheme.primaryGold.withOpacity(0.15), child: Text(widget.customer.name.isNotEmpty ? widget.customer.name[0] : '?', style: const TextStyle(fontSize: 20, color: AppTheme.primaryGold, fontWeight: FontWeight.bold))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.customer.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              if (widget.customer.contact != null) Text(widget.customer.contact!, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            ])),
          ]),
          const Divider(height: 20),
          if (widget.customer.phone != null) _buildInfoRow(Icons.phone, '电话', widget.customer.phone!),
          if (widget.customer.address != null) _buildInfoRow(Icons.location_on, '地址', widget.customer.address!),
          if (widget.customer.remark != null) _buildInfoRow(Icons.note, '备注', widget.customer.remark!),
        ]),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [Icon(icon, size: 16, color: AppTheme.textHint), const SizedBox(width: 8), Text('$label: ', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)), Expanded(child: Text(value, style: const TextStyle(fontSize: 13)))]));
  }

  Widget _buildStatsCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        childAspectRatio: 2.2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        children: [
          _statCard('交易总额', _stats['totalAmount'] ?? 0, AppTheme.primaryGold, Icons.monetization_on),
          _statCard('已收款', _stats['paid'] ?? 0, AppTheme.incomeGreen, Icons.check_circle),
          _statCard('未收款', _stats['unpaid'] ?? 0, AppTheme.warningOrange, Icons.pending),
          _statCard('毛利润', _stats['totalProfit'] ?? 0, AppTheme.infoBlue, Icons.trending_up),
        ],
      ),
    );
  }

  Widget _statCard(String label, double value, Color color, IconData icon) {
    return Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.2))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Row(children: [Icon(icon, size: 14, color: color), const SizedBox(width: 4), Text(label, style: TextStyle(fontSize: 11, color: color))]), const SizedBox(height: 4), Text('¥${value.toStringAsFixed(2)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color), maxLines: 1, overflow: TextOverflow.ellipsis)]));
  }

  Widget _buildIncomeItem(Income inc) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(radius: 18, backgroundColor: AppTheme.incomeGreen.withOpacity(0.15), child: const Icon(Icons.arrow_downward, size: 18, color: AppTheme.incomeGreen)),
        title: Text(inc.productName ?? '商品销售', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${inc.date} · ${inc.invoiceType == 'none' ? '不开票' : inc.invoiceType == 'general' ? '普票' : '专票'}', style: const TextStyle(fontSize: 11, color: AppTheme.textHint)),
        trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('¥${inc.amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.incomeGreen)),
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: inc.paymentStatus == 'paid' ? AppTheme.incomeGreen.withOpacity(0.1) : AppTheme.warningOrange.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text(inc.paymentStatus == 'paid' ? '已收' : '未收', style: TextStyle(fontSize: 10, color: inc.paymentStatus == 'paid' ? AppTheme.incomeGreen : AppTheme.warningOrange))),
        ]),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => IncomeFormPage(existingIncome: inc)));
          _loadData();
        },
      ),
    );
  }

  /// 导出该客户的对账单为Excel（客户信息+汇总+每笔明细）
  Future<void> _exportStatement() async {
    if (_incomes.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('该客户暂无交易记录，无法导出对账单')));
      return;
    }
    try {
      final excel = Excel.createExcel();
      excel.delete('Sheet1');
      final sheet = excel['客户对账单'];
      List<CellValue?> textRow(List<dynamic> vals) => vals.map((v) => TextCellValue('$v')).toList();

      sheet.appendRow(textRow(['客户对账单']));
      sheet.appendRow(textRow(['客户名称', widget.customer.name]));
      if (widget.customer.contact != null) sheet.appendRow(textRow(['联系人', widget.customer.contact!]));
      if (widget.customer.phone != null) sheet.appendRow(textRow(['电话', widget.customer.phone!]));
      if (widget.customer.address != null) sheet.appendRow(textRow(['地址', widget.customer.address!]));
      if (widget.customer.remark != null) sheet.appendRow(textRow(['备注', widget.customer.remark!]));
      sheet.appendRow(textRow(['导出时间', DateTime.now().toString().substring(0, 19)]));
      sheet.appendRow(textRow([]));
      sheet.appendRow(textRow(['===== 汇总 =====']));
      sheet.appendRow(textRow(['交易笔数', _incomes.length]));
      sheet.appendRow(textRow(['交易总额(价税合计)', (_stats['totalAmount'] ?? 0).toStringAsFixed(2)]));
      sheet.appendRow(textRow(['已收款', (_stats['paid'] ?? 0).toStringAsFixed(2)]));
      sheet.appendRow(textRow(['未收款', (_stats['unpaid'] ?? 0).toStringAsFixed(2)]));
      sheet.appendRow(textRow(['毛利润', (_stats['totalProfit'] ?? 0).toStringAsFixed(2)]));
      sheet.appendRow(textRow([]));
      sheet.appendRow(textRow(['===== 交易明细 =====']));
      sheet.appendRow(textRow(['日期', '采购内容', '数量', '单价', '金额(价税合计)', '成本', '发票类型', '税率', '税额', '不含税收入', '毛利', '收款状态', '收款日期', '备注']));
      for (var inc in _incomes) {
        sheet.appendRow(textRow([
          inc.date,
          inc.productName,
          inc.quantity?.toString() ?? '',
          inc.unitPrice?.toStringAsFixed(2) ?? '',
          inc.amount.toStringAsFixed(2),
          inc.cost.toStringAsFixed(2),
          inc.invoiceType == 'none' ? '不开票' : inc.invoiceType == 'general' ? '普票' : '专票',
          (inc.taxRate * 100).toStringAsFixed(0) + '%',
          inc.taxAmount.toStringAsFixed(2),
          inc.amountExcludingTax.toStringAsFixed(2),
          inc.grossProfit.toStringAsFixed(2),
          inc.paymentStatus == 'paid' ? '已收款' : '未收款',
          inc.paymentDate ?? '',
          inc.remark ?? '',
        ]));
      }

      final dir = await getTemporaryDirectory();
      final safeName = widget.customer.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final fileName = '对账单_${safeName}_${DateTime.now().toString().substring(0, 10).replaceAll('-', '')}.xlsx';
      final file = File('${dir.path}/$fileName');
      final bytes = excel.encode();
      await file.writeAsBytes(bytes!);
      await Share.shareXFiles([XFile(file.path, name: fileName)], text: '客户对账单 - ${widget.customer.name}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出对账单失败: $e'), backgroundColor: AppTheme.expenseRed));
    }
  }
}
