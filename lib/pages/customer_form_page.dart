import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/customer.dart';
import '../services/database_service.dart';

class CustomerFormPage extends StatefulWidget {
  final Customer? customer;
  const CustomerFormPage({super.key, this.customer});

  @override
  State<CustomerFormPage> createState() => _CustomerFormPageState();
}

class _CustomerFormPageState extends State<CustomerFormPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _contactController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _remarkController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.customer?.name ?? '');
    _contactController = TextEditingController(text: widget.customer?.contact ?? '');
    _phoneController = TextEditingController(text: widget.customer?.phone ?? '');
    _addressController = TextEditingController(text: widget.customer?.address ?? '');
    _remarkController = TextEditingController(text: widget.customer?.remark ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final now = DateTime.now().toIso8601String().substring(0, 19).replaceAll('T', ' ');
    final customer = Customer(
      id: widget.customer?.id,
      name: _nameController.text.trim(),
      contact: _contactController.text.trim().isEmpty ? null : _contactController.text.trim(),
      phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
      remark: _remarkController.text.trim().isEmpty ? null : _remarkController.text.trim(),
      createdAt: widget.customer?.createdAt ?? now,
      updatedAt: now,
    );
    try {
      if (widget.customer == null) {
        await DatabaseService.instance.insertCustomer(customer);
      } else {
        await DatabaseService.instance.updateCustomer(customer);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.customer == null ? '客户添加成功' : '客户更新成功')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e'), backgroundColor: AppTheme.expenseRed));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.customer == null ? '添加客户' : '编辑客户')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionTitle('基本信息'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '客户名称 *', hintText: '请输入客户名称', border: OutlineInputBorder(), prefixIcon: Icon(Icons.business)),
              validator: (v) => v == null || v.trim().isEmpty ? '请输入客户名称' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contactController,
              decoration: const InputDecoration(labelText: '联系人', hintText: '选填', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: '联系电话', hintText: '选填', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone)),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: '地址', hintText: '选填', border: OutlineInputBorder(), prefixIcon: Icon(Icons.location_on)),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('备注'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _remarkController,
              decoration: const InputDecoration(labelText: '备注', hintText: '选填', border: OutlineInputBorder(), prefixIcon: Icon(Icons.note)),
              maxLines: 3,
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(widget.customer == null ? '添加客户' : '保存修改', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(children: [Container(width: 4, height: 18, decoration: BoxDecoration(color: AppTheme.primaryGold, borderRadius: BorderRadius.circular(2))), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))]);
  }
}
