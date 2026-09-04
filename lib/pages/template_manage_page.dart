import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';

class TemplateManagePage extends StatefulWidget {
  const TemplateManagePage({super.key});

  @override
  State<TemplateManagePage> createState() => _TemplateManagePageState();
}

class _TemplateManagePageState extends State<TemplateManagePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Future<List<Map<String, dynamic>>> _incomeTemplates;
  late Future<List<Map<String, dynamic>>> _expenseTemplates;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadTemplates();
  }

  @override
  void dispose() {
    // 修复Ticker泄漏：反复进出模板管理页必须释放TabController，避免越用越卡/闪烁
    _tabController.dispose();
    super.dispose();
  }

  void _loadTemplates() {
    _incomeTemplates = DatabaseService.instance.getTemplates(type: 'income');
    _expenseTemplates = DatabaseService.instance.getTemplates(type: 'expense');
  }

  Future<void> _deleteTemplate(int id, String type) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模板'),
        content: const Text('确定要删除这个记账模板吗？'),
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
      await DatabaseService.instance.deleteTemplate(id);
      setState(() => _loadTemplates());
    }
  }

  Widget _buildTemplateList(Future<List<Map<String, dynamic>>> future, String type) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final templates = snapshot.data!;
        if (templates.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.note_add, size: 64, color: AppTheme.textHint),
                const SizedBox(height: 16),
                Text('暂无${type == 'income' ? '收入' : '支出'}模板', style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                const Text('在记账页面点击「保存为模板」即可创建', style: TextStyle(fontSize: 13, color: AppTheme.textHint)),
              ],
            ),
          );
        }
        return ListView.builder(
          itemCount: templates.length,
          itemBuilder: (context, index) {
            final t = templates[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                leading: Icon(
                  type == 'income' ? Icons.arrow_downward : Icons.arrow_upward,
                  color: type == 'income' ? AppTheme.incomeGreen : AppTheme.expenseRed,
                ),
                title: Text(t['name'] ?? '未命名模板'),
                subtitle: Text('创建于 ${t['created_at'] ?? ''}', style: const TextStyle(fontSize: 11)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: AppTheme.expenseRed),
                  onPressed: () => _deleteTemplate(t['id'] as int, type),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('记账模板'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: '收入模板'),
            Tab(text: '支出模板'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTemplateList(_incomeTemplates, 'income'),
          _buildTemplateList(_expenseTemplates, 'expense'),
        ],
      ),
    );
  }
}
