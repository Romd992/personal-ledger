import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/expense.dart';
import '../models/expense_type.dart';
import '../services/database_service.dart';
import '../providers/data_providers.dart';
import '../providers/settings_providers.dart';
import '../services/auto_backup_service.dart';
import '../theme/app_theme.dart';

// 数字输入格式化器：只允许数字和小数点
final numberInputFormatter = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

class ExpenseFormPage extends ConsumerStatefulWidget {
  final Expense? existingExpense;
  const ExpenseFormPage({super.key, this.existingExpense});

  @override
  ConsumerState<ExpenseFormPage> createState() => _ExpenseFormPageState();
}

class _ExpenseFormPageState extends ConsumerState<ExpenseFormPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _dateController;
  late TextEditingController _amountController;
  late TextEditingController _supplierNoteController;
  late TextEditingController _paymentDateController;
  late TextEditingController _remarkController;

  int? _expenseTypeId;
  String? _expenseTypeName;
  String _invoiceType = 'none';
  double _taxRate = 0.13;
  String _paymentStatus = 'paid';
  List<ExpenseType> _expenseTypes = [];
  double _taxAmount = 0;
  bool _isSaving = false; // 防止重复保存

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
    _dateController = TextEditingController(text: widget.existingExpense?.date ?? today);
    _amountController = TextEditingController(text: widget.existingExpense?.amount.toString() ?? '');
    _supplierNoteController = TextEditingController(text: widget.existingExpense?.supplierNote ?? '');
    _paymentDateController = TextEditingController(text: widget.existingExpense?.paymentDate ?? today);
    _remarkController = TextEditingController(text: widget.existingExpense?.remark ?? '');
    if (widget.existingExpense != null) {
      _expenseTypeId = widget.existingExpense!.expenseTypeId;
      _expenseTypeName = widget.existingExpense!.expenseTypeName;
      _invoiceType = widget.existingExpense!.invoiceType;
      _taxRate = widget.existingExpense!.taxRate;
      _paymentStatus = widget.existingExpense!.paymentStatus;
    }
    _loadExpenseTypes();
    _calculate();
  }

  @override
  void dispose() {
    _dateController.dispose();
    _amountController.dispose();
    _supplierNoteController.dispose();
    _paymentDateController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _loadExpenseTypes() async {
    final types = await DatabaseService.instance.getExpenseTypes();
    if (mounted) setState(() => _expenseTypes = types);
  }

  void _calculate() {
    final amount = double.tryParse(_amountController.text) ?? 0;
    final result = Expense.calculateTax(amount: amount, invoiceType: _invoiceType, taxRate: _taxRate);
    setState(() => _taxAmount = result['taxAmount']!);
  }

  Future<void> _selectDate(TextEditingController controller) async {
    final initial = DateTime.tryParse(controller.text) ?? DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2000), lastDate: DateTime(2300));
    if (picked != null) {
      controller.text = '${picked.year}-${picked.month.toString().padLeft(2,'0')}-${picked.day.toString().padLeft(2,'0')}';
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    FocusScope.of(context).unfocus();
    final formOk = _formKey.currentState?.validate() ?? false;
    // 手动二次校验金额，双保险
    final amountVal = double.tryParse(_amountController.text);
    if (!formOk || amountVal == null || amountVal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('请填写大于0的有效金额（必填）'),
        backgroundColor: AppTheme.expenseRed,
        duration: Duration(seconds: 2),
      ));
      return;
    }
    setState(() => _isSaving = true);
    final now = DateTime.now().toIso8601String();
    final amount = double.tryParse(_amountController.text) ?? 0;
    final result = Expense.calculateTax(amount: amount, invoiceType: _invoiceType, taxRate: _taxRate);

    // 类型名自动补全：有类型ID但名称为空时，从已加载列表中查找
    String? resolvedTypeName = _expenseTypeName;
    if (_expenseTypeId != null && (resolvedTypeName == null || resolvedTypeName.isEmpty)) {
      try {
        resolvedTypeName = _expenseTypes.firstWhere((t) => t.id == _expenseTypeId).name;
      } catch (_) {}
    }

    final expense = Expense(
      id: widget.existingExpense?.id,
      date: _dateController.text,
      amount: amount,
      expenseTypeId: _expenseTypeId,
      expenseTypeName: resolvedTypeName,
      supplierNote: _supplierNoteController.text.trim().isEmpty ? null : _supplierNoteController.text.trim(),
      invoiceType: _invoiceType,
      taxRate: _taxRate,
      taxAmount: result['taxAmount']!,
      paymentStatus: _paymentStatus,
      paymentDate: _paymentStatus == 'paid' ? _paymentDateController.text : null,
      remark: _remarkController.text.trim().isEmpty ? null : _remarkController.text.trim(),
      bookId: widget.existingExpense?.bookId ?? ref.read(currentBookIdProvider),
      createdAt: widget.existingExpense?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      if (widget.existingExpense == null) {
        await DatabaseService.instance.insertExpense(expense);
      } else {
        await DatabaseService.instance.updateExpense(expense);
      }
      if (mounted) {
        ref.invalidate(expensesProvider);
        ref.invalidate(expenseStatsProvider);
        ref.read(refreshTriggerProvider.notifier).state++;
        // 自动备份
        AutoBackupService.executeBackup();
        final msg = widget.existingExpense == null ? '支出记录已添加' : '支出记录已更新';
        Navigator.pop(context, true);
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingExpense == null ? '记支出' : '编辑支出'),
        actions: [
          IconButton(icon: const Icon(Icons.content_paste), tooltip: '选择模板', onPressed: _showTemplatePicker),
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: Text(_isSaving ? '保存中...' : '保存', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildLabel('日期 *'),
            TextFormField(controller: _dateController, readOnly: true, onTap: () => _selectDate(_dateController), decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today, size: 18)), validator: (v) => v?.isEmpty ?? true ? '请选择日期' : null),
            const SizedBox(height: 16),
            _buildLabel('金额 *'),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: numberInputFormatter,
              decoration: const InputDecoration(prefixText: '¥ ', hintText: '0.00'),
              validator: (v) { final val = double.tryParse(v ?? ''); if (val == null || val <= 0) return '请输入有效金额'; return null; },
              onChanged: (_) => _calculate(),
            ),
            const SizedBox(height: 16),
            _buildLabel('支出类型'),
            DropdownButtonFormField<int>(
              value: _expenseTypeId,
              decoration: const InputDecoration(hintText: '请选择支出类型'),
              items: _expenseTypes.map((t) => DropdownMenuItem<int>(value: t.id, child: Text(t.name))).toList(),
              onChanged: (v) {
                if (v == null) return;
                try {
                  final type = _expenseTypes.firstWhere((t) => t.id == v, orElse: () => _expenseTypes.first);
                  setState(() { _expenseTypeId = v; _expenseTypeName = type.name; });
                } catch (_) {
                  setState(() { _expenseTypeId = v; });
                }
              },
            ),
            const SizedBox(height: 16),
            _buildLabel('供应商/说明（选填）'),
            TextFormField(controller: _supplierNoteController, decoration: const InputDecoration(hintText: '如：XX五金店 购买零件')),
            const SizedBox(height: 16),
            _buildLabel('发票类型'),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'none', label: Text('不开票')), ButtonSegment(value: 'general', label: Text('普票')), ButtonSegment(value: 'special', label: Text('专票'))],
              selected: {_invoiceType},
              onSelectionChanged: (s) {
                setState(() {
                  _invoiceType = s.first;
                  // 自动套用「设置-默认税率预设」
                  if (_invoiceType == 'general') {
                    _taxRate = ref.read(generalTaxRateProvider);
                  } else if (_invoiceType == 'special') {
                    _taxRate = ref.read(specialTaxRateProvider);
                  }
                  _calculate();
                });
              },
            ),
            if (_invoiceType != 'none') ...[
              const SizedBox(height: 16),
              _buildLabel('税率'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [0.01, 0.03, 0.06, 0.09, 0.13].map((rate) => ChoiceChip(
                  label: Text('${(rate*100).toInt()}%'),
                  selected: (_taxRate - rate).abs() < 0.000001,
                  onSelected: (_) => setState(() { _taxRate = rate; _calculate(); }),
                )).toList()
                  ..add(ChoiceChip(
                    label: const Text('自定义'),
                    selected: ![0.01, 0.03, 0.06, 0.09, 0.13].any((r) => (_taxRate - r).abs() < 0.000001),
                    onSelected: (_) async {
                      final ctrl = TextEditingController(text: (_taxRate*100).toString());
                      final result = await showDialog<double>(context: context, builder: (ctx) => AlertDialog(
                        title: const Text('自定义税率'),
                        content: TextField(controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(suffixText: '%')),
                        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), TextButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text)), child: const Text('确定'))],
                      ));
                      if (result != null && result >= 0 && result <= 100) { setState(() { _taxRate = result / 100; _calculate(); }); }
                    },
                  )),
              ),
              const SizedBox(height: 12),
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppTheme.bgWarm, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('进项税额', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                  Text('¥${_taxAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.infoBlue)),
                ]),
              ),
            ],
            const SizedBox(height: 16),
            _buildLabel('付款状态'),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'paid', label: Text('已付款')), ButtonSegment(value: 'unpaid', label: Text('未付款'))],
              selected: {_paymentStatus},
              onSelectionChanged: (s) => setState(() => _paymentStatus = s.first),
            ),
            if (_paymentStatus == 'paid') ...[
              const SizedBox(height: 16),
              _buildLabel('付款日期'),
              TextFormField(controller: _paymentDateController, readOnly: true, onTap: () => _selectDate(_paymentDateController), decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today, size: 18))),
            ],
            const SizedBox(height: 16),
            _buildLabel('备注（选填）'),
            TextFormField(controller: _remarkController, maxLines: 3, decoration: const InputDecoration(hintText: '其他备注信息')),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _isSaving ? null : _save, child: Text(_isSaving ? '保存中...' : (widget.existingExpense == null ? '保存支出记录' : '更新支出记录'), style: const TextStyle(fontSize: 16)))),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _saveAsTemplate, icon: const Icon(Icons.bookmark_border), label: const Text('保存为模板'), style: OutlinedButton.styleFrom(foregroundColor: AppTheme.expenseRed, side: const BorderSide(color: AppTheme.expenseRed)))),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)));

  // 显示模板选择器
  Future<void> _showTemplatePicker() async {
    final templates = await DatabaseService.instance.getTemplates(type: 'expense');
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            const Text('选择支出模板', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
          ])),
          if (templates.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Text('暂无模板，填写后点击"保存为模板"', style: TextStyle(color: AppTheme.textHint))),
          ...templates.map((t) => ListTile(
            leading: const Icon(Icons.receipt, color: AppTheme.expenseRed),
            title: Text(t['name'] as String),
            subtitle: Text(t['created_at'] as String, style: const TextStyle(fontSize: 11)),
            trailing: IconButton(icon: const Icon(Icons.delete_outline, color: AppTheme.expenseRed), onPressed: () async {
              await DatabaseService.instance.deleteTemplate(t['id'] as int);
              if (ctx.mounted) Navigator.pop(ctx);
              _showTemplatePicker();
            }),
            onTap: () {
              _applyTemplate(t);
              Navigator.pop(ctx);
            },
          )),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  // 应用模板到表单
  void _applyTemplate(Map<String, dynamic> template) {
    try {
      final content = jsonDecode(template['content'] as String) as Map<String, dynamic>;
      if (content['amount'] != null) _amountController.text = content['amount'].toString();
      if (content['supplierNote'] != null) _supplierNoteController.text = content['supplierNote'];
      if (content['invoiceType'] != null) _invoiceType = content['invoiceType'];
      if (content['taxRate'] != null) _taxRate = content['taxRate'];
      if (content['paymentStatus'] != null) _paymentStatus = content['paymentStatus'];
      if (content['remark'] != null) _remarkController.text = content['remark'];
      if (content['expenseTypeId'] != null && _expenseTypes.isNotEmpty) {
        final type = _expenseTypes.where((t) => t.id == content['expenseTypeId']);
        if (type.isNotEmpty) {
          _expenseTypeId = type.first.id;
          _expenseTypeName = type.first.name;
        }
      }
      _calculate();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('模板已应用')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('模板应用失败: $e'), backgroundColor: AppTheme.expenseRed));
    }
  }

  // 保存为模板
  Future<void> _saveAsTemplate() async {
    final nameCtrl = TextEditingController(text: _expenseTypeName ?? '支出模板');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存为模板'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(hintText: '请输入模板名称', labelText: '模板名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    final content = jsonEncode({
      'amount': double.tryParse(_amountController.text) ?? 0,
      'expenseTypeId': _expenseTypeId,
      'expenseTypeName': _expenseTypeName,
      'supplierNote': _supplierNoteController.text,
      'invoiceType': _invoiceType,
      'taxRate': _taxRate,
      'paymentStatus': _paymentStatus,
      'remark': _remarkController.text,
    });
    await DatabaseService.instance.insertTemplate('expense', result, content);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('模板已保存')));
  }
}
