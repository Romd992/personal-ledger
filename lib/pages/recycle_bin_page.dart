import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../models/recycle_item.dart';
import '../services/database_service.dart';
import '../providers/settings_providers.dart';
import '../providers/data_providers.dart';

class RecycleBinPage extends ConsumerStatefulWidget {
  const RecycleBinPage({super.key});

  @override
  ConsumerState<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends ConsumerState<RecycleBinPage> {
  late Future<List<RecycleItem>> _itemsFuture;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  void _loadItems() {
    _itemsFuture = DatabaseService.instance.getRecycleItems();
  }

  Future<void> _restoreItem(RecycleItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('还原记录'),
        content: Text('确定要还原这条${item.recordType == 'income' ? '收入' : '支出'}记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('还原')),
        ],
      ),
    );
    if (confirm == true) {
      if (item.recordType == 'income') {
        await DatabaseService.instance.restoreIncome(item);
      } else {
        await DatabaseService.instance.restoreExpense(item);
      }
      setState(() => _loadItems());
      ref.invalidate(recycleBinCountProvider);
      // 显式刷新收支列表，避免 IndexedStack 保活页面回到列表时仍显示还原前的旧缓存
      ref.invalidate(incomesProvider);
      ref.invalidate(expensesProvider);
      // 还原会把记录写回主表，需递增全局刷新信号，让首页/列表/税务/统计同步更新
      ref.read(refreshTriggerProvider.notifier).state++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('记录已还原')));
      }
    }
  }

  Future<void> _deletePermanently(RecycleItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底删除', style: TextStyle(color: AppTheme.expenseRed)),
        content: const Text('确定要彻底删除这条记录吗？此操作不可恢复！'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.expenseRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await DatabaseService.instance.deleteRecycleItem(item.id!);
      setState(() => _loadItems());
      ref.invalidate(recycleBinCountProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已彻底删除')));
      }
    }
  }

  Future<void> _restoreAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('全部还原'),
        content: const Text('确定要还原回收站中的所有记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('全部还原')),
        ],
      ),
    );
    if (confirm == true) {
      final items = await DatabaseService.instance.getRecycleItems();
      for (var item in items) {
        if (item.recordType == 'income') {
          await DatabaseService.instance.restoreIncome(item);
        } else {
          await DatabaseService.instance.restoreExpense(item);
        }
      }
      setState(() => _loadItems());
      ref.invalidate(recycleBinCountProvider);
      // 显式刷新收支列表，避免批量还原后回到列表仍显示旧缓存
      ref.invalidate(incomesProvider);
      ref.invalidate(expensesProvider);
      // 全部还原会批量写回主表，需同步刷新所有数据页面
      ref.read(refreshTriggerProvider.notifier).state++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('所有记录已还原')));
      }
    }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空回收站', style: TextStyle(color: AppTheme.expenseRed)),
        content: const Text('确定要清空回收站吗？所有记录将被彻底删除，不可恢复！'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.expenseRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await DatabaseService.instance.clearRecycleBin();
      setState(() => _loadItems());
      ref.invalidate(recycleBinCountProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('回收站已清空')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        actions: [
          TextButton.icon(
            onPressed: _restoreAll,
            icon: const Icon(Icons.restore, color: Colors.white),
            label: const Text('全部还原', style: TextStyle(color: Colors.white)),
          ),
          TextButton.icon(
            onPressed: _clearAll,
            icon: const Icon(Icons.delete_forever, color: Colors.white),
            label: const Text('清空', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: FutureBuilder<List<RecycleItem>>(
        future: _itemsFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_sweep, size: 64, color: AppTheme.textHint),
                  SizedBox(height: 16),
                  Text('回收站为空', style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                  SizedBox(height: 8),
                  Text('删除的记录会在这里保留30天', style: TextStyle(fontSize: 13, color: AppTheme.textHint)),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final isIncome = item.recordType == 'income';
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (isIncome ? AppTheme.incomeGreen : AppTheme.expenseRed).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                      color: isIncome ? AppTheme.incomeGreen : AppTheme.expenseRed,
                    ),
                  ),
                  title: Text(item.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            isIncome ? '收入' : '支出',
                            style: TextStyle(fontSize: 11, color: isIncome ? AppTheme.incomeGreen : AppTheme.expenseRed),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item.displayAmount,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isIncome ? AppTheme.incomeGreen : AppTheme.expenseRed,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('删除于 ${item.deletedAt}，${item.expireAt} 后自动清除', style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.restore, color: AppTheme.primaryGold),
                        tooltip: '还原',
                        onPressed: () => _restoreItem(item),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever, color: AppTheme.expenseRed),
                        tooltip: '彻底删除',
                        onPressed: () => _deletePermanently(item),
                      ),
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
