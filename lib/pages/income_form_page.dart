import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../models/income.dart';
import '../services/database_service.dart';
import '../services/image_compress_service.dart';
import '../services/platform_file_service.dart';
import '../providers/data_providers.dart';
import '../providers/settings_providers.dart';
import '../services/auto_backup_service.dart';
import '../theme/app_theme.dart';

// 数字输入格式化器：只允许数字和小数点
final numberInputFormatter = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

class IncomeFormPage extends ConsumerStatefulWidget {
  final Income? existingIncome; // 编辑时传入
  final String? initialCustomer; // 新增时预填客户名称
  const IncomeFormPage({super.key, this.existingIncome, this.initialCustomer});

  @override
  ConsumerState<IncomeFormPage> createState() => _IncomeFormPageState();
}

class _IncomeFormPageState extends ConsumerState<IncomeFormPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _dateController;
  late TextEditingController _customerController;
  late TextEditingController _productController;
  late TextEditingController _quantityController;
  late TextEditingController _unitPriceController;
  late TextEditingController _amountController;
  late TextEditingController _costController;
  late TextEditingController _paymentDateController;
  late TextEditingController _remarkController;
  late FocusNode _customerFocusNode;

  String _invoiceType = 'none'; // none/general/special
  double _taxRate = 0.13;
  String _paymentStatus = 'paid';
  List<String> _customerSuggestions = [];
  bool _showSuggestions = false;
  bool _suppressSuggest = false; // 选中联想项时临时抑制，避免赋值触发listener又弹出列表
  bool _isSaving = false; // 防止重复保存
  List<String> _voucherImages = []; // 凭证图片路径列表

  // 计算结果
  double _taxAmount = 0;
  double _amountExcludingTax = 0;
  double _grossProfit = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
    _dateController = TextEditingController(text: widget.existingIncome?.date ?? today);
    _customerController = TextEditingController(text: widget.existingIncome?.customerName ?? widget.initialCustomer ?? '');
    _productController = TextEditingController(text: widget.existingIncome?.productName ?? '');
    _quantityController = TextEditingController(text: widget.existingIncome?.quantity?.toString() ?? '');
    _unitPriceController = TextEditingController(text: widget.existingIncome?.unitPrice?.toString() ?? '');
    _amountController = TextEditingController(text: widget.existingIncome != null ? widget.existingIncome!.amount.toStringAsFixed(2) : '');
    // 成本不再预填黑色实体0，新增时留空、用灰色hint提示；编辑时仅在成本>0时回显（统一两位小数）
    _costController = TextEditingController(text: (widget.existingIncome != null && widget.existingIncome!.cost > 0) ? widget.existingIncome!.cost.toStringAsFixed(2) : '');
    _paymentDateController = TextEditingController(text: widget.existingIncome?.paymentDate ?? today);
    _remarkController = TextEditingController(text: widget.existingIncome?.remark ?? '');
    if (widget.existingIncome != null) {
      _invoiceType = widget.existingIncome!.invoiceType;
      _taxRate = widget.existingIncome!.taxRate;
      _paymentStatus = widget.existingIncome!.paymentStatus;
      _voucherImages = List<String>.from(widget.existingIncome!.voucherImages ?? []);
    }
    _calculate();
    _customerController.addListener(_onCustomerChanged);
    _customerFocusNode = FocusNode();
    _customerFocusNode.addListener(() {
      if (!_customerFocusNode.hasFocus) {
        setState(() => _showSuggestions = false);
      }
    });
  }

  @override
  void dispose() {
    _customerController.removeListener(_onCustomerChanged);
    _dateController.dispose();
    _customerController.dispose();
    _productController.dispose();
    _quantityController.dispose();
    _unitPriceController.dispose();
    _amountController.dispose();
    _costController.dispose();
    _paymentDateController.dispose();
    _remarkController.dispose();
    _customerFocusNode.dispose();
    super.dispose();
  }

  void _onCustomerChanged() {
    // 刚通过联想项填入时，跳过本次由程序赋值触发的查询，防止列表重新弹出残留
    if (_suppressSuggest) {
      _suppressSuggest = false;
      return;
    }
    if (_customerController.text.isNotEmpty) {
      _loadSuggestions(_customerController.text);
    } else {
      setState(() => _showSuggestions = false);
    }
  }

  Future<void> _loadSuggestions(String keyword) async {
    // 取消8条上限，返回全部匹配项（弹窗内部可上下滚动）
    final names = await DatabaseService.instance.getCustomerNames(keyword: keyword);
    if (mounted) {
      setState(() {
        _customerSuggestions = names;
        _showSuggestions = _customerSuggestions.isNotEmpty && _customerController.text.isNotEmpty;
      });
    }
  }

  void _calculate() {
    final amount = double.tryParse(_amountController.text) ?? 0;
    final cost = double.tryParse(_costController.text) ?? 0;
    final result = Income.calculate(amount: amount, cost: cost, invoiceType: _invoiceType, taxRate: _taxRate);
    setState(() {
      _taxAmount = result['taxAmount']!;
      _amountExcludingTax = result['amountExcludingTax']!;
      _grossProfit = result['grossProfit']!;
    });
  }

  Future<void> _selectDate(TextEditingController controller) async {
    final initial = DateTime.tryParse(controller.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2300),
    );
    if (picked != null) {
      controller.text = '${picked.year}-${picked.month.toString().padLeft(2,'0')}-${picked.day.toString().padLeft(2,'0')}';
    }
  }

  // 轻提示
  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppTheme.expenseRed, duration: const Duration(seconds: 2)));
  }

  /// 构建凭证图片区域
  Widget _buildVoucherImages() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_voucherImages.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._voucherImages.asMap().entries.map((entry) {
                final index = entry.key;
                final path = entry.value;
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(path),
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _voucherImages.removeAt(index));
                        },
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        const SizedBox(height: 8),
        if (PlatformFileService.isWindows)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _pickVoucherImageWindows(),
              icon: const Icon(Icons.file_upload, size: 18),
              label: const Text('选择凭证图片文件'),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primaryGold, side: const BorderSide(color: AppTheme.primaryGold)),
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickVoucherImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: const Text('拍照'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primaryGold, side: const BorderSide(color: AppTheme.primaryGold)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickVoucherImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library, size: 18),
                  label: const Text('从相册选择'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primaryGold, side: const BorderSide(color: AppTheme.primaryGold)),
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// Windows平台：从文件选择器选择凭证图片
  Future<void> _pickVoucherImageWindows() async {
    try {
      final file = await PlatformFileService.pickImage(dialogTitle: '选择凭证图片');
      if (file == null) return;

      showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

      final compressedPath = await ImageCompressService.compressImage(file.path);

      if (mounted) {
        Navigator.pop(context);
        setState(() => _voucherImages.add(compressedPath));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加图片失败：$e')),
        );
      }
    }
  }

  /// 选择凭证图片（拍照或相册）- Android/iOS
  Future<void> _pickVoucherImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (image == null) return;

      // 显示加载
      showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

      // 压缩图片
      final compressedPath = await ImageCompressService.compressImage(image.path);

      if (mounted) {
        Navigator.pop(context); // 关闭加载
        setState(() => _voucherImages.add(compressedPath));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加图片失败：$e')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (_isSaving) return; // 防止重复点击
    // 先收起键盘
    FocusScope.of(context).unfocus();
    // 表单校验（标红提示）
    final formOk = _formKey.currentState?.validate() ?? false;
    // 手动二次校验必填项，双保险，确保空值绝不可能保存
    final customer = _customerController.text.trim();
    final product = _productController.text.trim();
    final amountVal = double.tryParse(_amountController.text);
    if (!formOk || customer.isEmpty || product.isEmpty || amountVal == null || amountVal < 0) {
      if (customer.isEmpty) {
        _toast('请填写客户名称（必填）');
      } else if (product.isEmpty) {
        _toast('请填写采购内容（必填）');
      } else if (amountVal == null || amountVal < 0) {
        _toast('请输入有效金额（不能为负数，0元表示赠送）');
      }
      return;
    }
    setState(() => _isSaving = true);
    final now = DateTime.now().toIso8601String();
    final amount = double.tryParse(_amountController.text) ?? 0;
    final cost = double.tryParse(_costController.text) ?? 0;
    final result = Income.calculate(amount: amount, cost: cost, invoiceType: _invoiceType, taxRate: _taxRate);

    final income = Income(
      id: widget.existingIncome?.id,
      date: _dateController.text,
      customerName: _customerController.text.trim(),
      productName: _productController.text.trim(),
      quantity: double.tryParse(_quantityController.text),
      unitPrice: double.tryParse(_unitPriceController.text),
      amount: amount,
      cost: cost,
      invoiceType: _invoiceType,
      taxRate: _taxRate,
      taxAmount: result['taxAmount']!,
      amountExcludingTax: result['amountExcludingTax']!,
      grossProfit: result['grossProfit']!,
      paymentStatus: _paymentStatus,
      paymentDate: _paymentStatus == 'paid' ? _paymentDateController.text : null,
      remark: _remarkController.text.trim().isEmpty ? null : _remarkController.text.trim(),
      bookId: widget.existingIncome?.bookId ?? ref.read(currentBookIdProvider),
      voucherImages: _voucherImages.isEmpty ? null : List<String>.from(_voucherImages),
      createdAt: widget.existingIncome?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      if (widget.existingIncome == null) {
        await DatabaseService.instance.insertIncome(income);
      } else {
        await DatabaseService.instance.updateIncome(income);
      }
      if (mounted) {
        ref.invalidate(incomesProvider);
        ref.invalidate(incomeStatsProvider);
        ref.read(refreshTriggerProvider.notifier).state++;
        // 自动备份
        AutoBackupService.executeBackup();
        final msg = widget.existingIncome == null ? '收入记录已添加' : '收入记录已更新';
        Navigator.pop(context, true);
        // 延迟显示SnackBar，确保页面已pop
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingIncome == null ? '记收入' : '编辑收入'),
        actions: [
          IconButton(icon: const Icon(Icons.content_paste), tooltip: '选择模板', onPressed: _showTemplatePicker),
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: Text(_isSaving ? '保存中...' : '保存', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() => _showSuggestions = false);
        },
        child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 日期
            _buildLabel('日期 *'),
            TextFormField(
              controller: _dateController,
              readOnly: true,
              onTap: () => _selectDate(_dateController),
              decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today, size: 18)),
              validator: (v) => v?.isEmpty ?? true ? '请选择日期' : null,
            ),
            const SizedBox(height: 16),
            // 客户名称（带联想）
            _buildLabel('客户名称 *'),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _customerController,
                  focusNode: _customerFocusNode,
                  decoration: const InputDecoration(hintText: '输入客户名称，支持联想'),
                  validator: (v) => v?.trim().isEmpty ?? true ? '请输入客户名称' : null,
                  onFieldSubmitted: (_) => setState(() => _showSuggestions = false),
                ),
                if (_showSuggestions)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    constraints: const BoxConstraints(maxHeight: 220), // 限制高度，超出可滚动，显示全部匹配客户
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.divider), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: _customerSuggestions.map((name) => ListTile(
                        dense: true,
                        title: Text(name, style: const TextStyle(fontSize: 14)),
                        leading: const Icon(Icons.person, size: 18, color: AppTheme.primaryGold),
                        onTap: () {
                          // 先置抑制标志，避免给 controller 赋值时触发监听又弹出联想
                          _suppressSuggest = true;
                          _customerController.text = name;
                          _customerController.selection = TextSelection.fromPosition(TextPosition(offset: name.length));
                          setState(() {
                            _showSuggestions = false;
                            _customerSuggestions = [];
                          });
                          // 收起键盘
                          FocusScope.of(context).unfocus();
                        },
                      )).toList(),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // 采购内容
            _buildLabel('采购内容 *'),
            TextFormField(
              controller: _productController,
              decoration: const InputDecoration(hintText: '如：购买机器一台'),
              validator: (v) => v?.trim().isEmpty ?? true ? '请输入采购内容' : null,
            ),
            const SizedBox(height: 16),
            // 数量 + 单价
            Row(
              children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _buildLabel('数量（选填）'),
                  TextFormField(
                    controller: _quantityController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: numberInputFormatter,
                    decoration: const InputDecoration(hintText: '如：2'),
                    onChanged: (_) => _autoCalcAmount(),
                  ),
                ])),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _buildLabel('单价（选填）'),
                  TextFormField(
                    controller: _unitPriceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: numberInputFormatter,
                    decoration: const InputDecoration(hintText: '如：50'),
                    onChanged: (_) => _autoCalcAmount(),
                  ),
                ])),
              ],
            ),
            const SizedBox(height: 16),
            // 金额
            _buildLabel('金额（价税合计）*'),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: numberInputFormatter,
              readOnly: _quantityController.text.isNotEmpty && _unitPriceController.text.isNotEmpty,
              decoration: InputDecoration(
                prefixText: '¥ ',
                hintText: '0.00',
                helperText: _quantityController.text.isNotEmpty && _unitPriceController.text.isNotEmpty ? '已由数量×单价自动计算' : null,
                helperStyle: const TextStyle(fontSize: 11, color: AppTheme.primaryGold),
              ),
              validator: (v) {
                final val = double.tryParse(v ?? '');
                if (val == null || val < 0) return '请输入有效金额（0元表示赠送）';
                return null;
              },
              onChanged: (_) => _calculate(),
            ),
            const SizedBox(height: 16),
            // 成本
            _buildLabel('成本（选填，用于计算毛利）'),
            TextFormField(
              controller: _costController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: numberInputFormatter,
              // 灰色提示文字，不预填黑色实体0；点击可直接输入，无需先删除
              decoration: const InputDecoration(prefixText: '¥ ', hintText: '0.00（选填，可留空）'),
              onChanged: (_) => _calculate(),
            ),
            const SizedBox(height: 16),
            // 发票类型
            _buildLabel('发票类型'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'none', label: Text('不开票')),
                ButtonSegment(value: 'general', label: Text('普票')),
                ButtonSegment(value: 'special', label: Text('专票')),
              ],
              selected: {_invoiceType},
              onSelectionChanged: (s) {
                setState(() {
                  _invoiceType = s.first;
                  // 选择发票类型时自动套用「设置-默认税率预设」中的税率
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
                children: [0.01, 0.03, 0.06, 0.09, 0.13].map((rate) => ChoiceChip(
                  label: Text('${(rate*100).toInt()}%'),
                  selected: _taxRate == rate,
                  onSelected: (_) => setState(() { _taxRate = rate; _calculate(); }),
                )).toList()
                  ..add(ChoiceChip(
                    label: const Text('自定义'),
                    selected: ![0.01,0.03,0.06,0.09,0.13].contains(_taxRate),
                    onSelected: (_) async {
                      final ctrl = TextEditingController(text: (_taxRate*100).toString());
                      final result = await showDialog<double>(context: context, builder: (ctx) => AlertDialog(
                        title: const Text('自定义税率'),
                        content: TextField(controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(suffixText: '%')),
                        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), TextButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text) ?? 0), child: const Text('确定'))],
                      ));
                      if (result != null && result > 0) { setState(() { _taxRate = result / 100; _calculate(); }); }
                    },
                  )),
              ),
            ],
            const SizedBox(height: 16),
            // 计算结果展示
            _buildCalcResult(),
            const SizedBox(height: 16),
            // 收款状态
            _buildLabel('收款状态'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'paid', label: Text('已收款')),
                ButtonSegment(value: 'unpaid', label: Text('未收款')),
              ],
              selected: {_paymentStatus},
              onSelectionChanged: (s) => setState(() => _paymentStatus = s.first),
            ),
            if (_paymentStatus == 'paid') ...[
              const SizedBox(height: 16),
              _buildLabel('收款日期'),
              TextFormField(controller: _paymentDateController, readOnly: true, onTap: () => _selectDate(_paymentDateController), decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today, size: 18))),
            ],
            const SizedBox(height: 16),
            // 备注
            _buildLabel('备注（选填）'),
            TextFormField(controller: _remarkController, maxLines: 3, decoration: const InputDecoration(hintText: '其他备注信息')),
            const SizedBox(height: 16),
            // 凭证图片
            _buildLabel('凭证图片（选填，可多张）'),
            _buildVoucherImages(),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _isSaving ? null : _save, child: Text(_isSaving ? '保存中...' : (widget.existingIncome == null ? '保存收入记录' : '更新收入记录'), style: const TextStyle(fontSize: 16)))),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _saveAsTemplate, icon: const Icon(Icons.bookmark_border), label: const Text('保存为模板'), style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primaryGold, side: const BorderSide(color: AppTheme.primaryGold)))),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );
  }

  void _autoCalcAmount() {
    final qty = double.tryParse(_quantityController.text);
    final price = double.tryParse(_unitPriceController.text);
    if (qty != null && price != null) {
      _amountController.text = (qty * price).toStringAsFixed(2);
      _calculate();
    }
    // 更新UI以反映金额只读状态
    if (mounted) setState(() {});
  }

  // 显示模板选择器
  Future<void> _showTemplatePicker() async {
    final templates = await DatabaseService.instance.getTemplates(type: 'income');
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            const Text('选择收入模板', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
          ])),
          if (templates.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Text('暂无模板，填写后点击"保存为模板"', style: TextStyle(color: AppTheme.textHint))),
          ...templates.map((t) => ListTile(
            leading: const Icon(Icons.receipt, color: AppTheme.incomeGreen),
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
      if (content['customerName'] != null) _customerController.text = content['customerName'];
      if (content['productName'] != null) _productController.text = content['productName'];
      if (content['quantity'] != null) _quantityController.text = content['quantity'].toString();
      if (content['unitPrice'] != null) _unitPriceController.text = content['unitPrice'].toString();
      if (content['amount'] != null) _amountController.text = (content['amount'] as num).toDouble().toStringAsFixed(2);
      if (content['cost'] != null) _costController.text = (content['cost'] as num).toDouble().toStringAsFixed(2);
      if (content['invoiceType'] != null) _invoiceType = content['invoiceType'];
      if (content['taxRate'] != null) _taxRate = content['taxRate'];
      if (content['paymentStatus'] != null) _paymentStatus = content['paymentStatus'];
      if (content['remark'] != null) _remarkController.text = content['remark'];
      _calculate();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('模板已应用')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('模板应用失败: $e'), backgroundColor: AppTheme.expenseRed));
    }
  }

  // 保存为模板
  Future<void> _saveAsTemplate() async {
    final nameCtrl = TextEditingController(text: _customerController.text.isNotEmpty ? '${_customerController.text}-${_productController.text}' : '');
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
      'customerName': _customerController.text,
      'productName': _productController.text,
      'quantity': double.tryParse(_quantityController.text),
      'unitPrice': double.tryParse(_unitPriceController.text),
      'amount': double.tryParse(_amountController.text) ?? 0,
      'cost': double.tryParse(_costController.text) ?? 0,
      'invoiceType': _invoiceType,
      'taxRate': _taxRate,
      'paymentStatus': _paymentStatus,
      'remark': _remarkController.text,
    });
    await DatabaseService.instance.insertTemplate('income', result, content);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('模板已保存')));
  }

  Widget _buildLabel(String text) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)));

  Widget _buildCalcResult() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.bgWarm, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
      child: Column(
        children: [
          _calcRow('价税合计', '¥${_amountController.text.isEmpty ? '0.00' : (double.tryParse(_amountController.text) ?? 0).toStringAsFixed(2)}', AppTheme.textPrimary),
          _calcRow('税率', _invoiceType == 'none' ? '不开票' : '${(_taxRate*100).toStringAsFixed(0)}%', AppTheme.textSecondary),
          _calcRow('税额', '¥${_taxAmount.toStringAsFixed(2)}', AppTheme.warningOrange),
          _calcRow('不含税收入', '¥${_amountExcludingTax.toStringAsFixed(2)}', AppTheme.infoBlue),
          const Divider(height: 16),
          _calcRow('成本', '¥${(double.tryParse(_costController.text) ?? 0).toStringAsFixed(2)}', AppTheme.textSecondary),
          _calcRow('毛利（不含税收入-成本）', '¥${_grossProfit.toStringAsFixed(2)}', _grossProfit >= 0 ? AppTheme.incomeGreen : AppTheme.expenseRed, bold: true),
        ],
      ),
    );
  }

  Widget _calcRow(String label, String value, Color color, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
      Text(value, style: TextStyle(fontSize: 13, color: color, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
    ]),
  );
}
