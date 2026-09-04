import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/expense_type.dart';
import '../services/database_service.dart';

class ExpenseTypeManagePage extends StatefulWidget {
  const ExpenseTypeManagePage({super.key});

  @override
  State<ExpenseTypeManagePage> createState() => _ExpenseTypeManagePageState();
}

class _ExpenseTypeManagePageState extends State<ExpenseTypeManagePage> {
  late Future<List<ExpenseType>> _typesFuture;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  void _loadTypes() {
    _typesFuture = DatabaseService.instance.getExpenseTypes();
  }

  Future<void> _addType() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增支出类型'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '类型名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('添加')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      final type = ExpenseType(name: result, sortOrder: 99, isBuiltIn: false);
      await DatabaseService.instance.insertExpenseType(type);
      setState(() => _loadTypes());
    }
  }

  Future<void> _renameType(ExpenseType type) async {
    final controller = TextEditingController(text: type.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改支出类型'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '类型名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await DatabaseService.instance.updateExpenseType(type.copyWith(name: result));
      setState(() => _loadTypes());
    }
  }

  Future<void> _deleteType(ExpenseType type) async {
    if (type.isBuiltIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('内置类型不可删除')));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除支出类型'),
        content: Text('确定要删除「${type.name}」吗？已使用该类型的记录不受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.expenseRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await DatabaseService.instance.deleteExpenseType(type.id!);
      setState(() => _loadTypes());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('支出类型管理'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _addType),
        ],
      ),
      body: FutureBuilder<List<ExpenseType>>(
        future: _typesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final types = snapshot.data!;
          return ListView.builder(
            itemCount: types.length,
            itemBuilder: (context, index) {
              final type = types[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: const Icon(Icons.category, color: AppTheme.primaryGold),
                  title: Row(
                    children: [
                      Text(type.name),
                      if (type.isBuiltIn) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppTheme.primaryGold.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                          child: const Text('内置', style: TextStyle(fontSize: 11, color: AppTheme.primaryGold)),
                        ),
                      ],
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit, color: AppTheme.textSecondary), onPressed: () => _renameType(type)),
                      if (!type.isBuiltIn)
                        IconButton(icon: const Icon(Icons.delete, color: AppTheme.expenseRed), onPressed: () => _deleteType(type)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
