import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../models/book.dart';
import '../services/database_service.dart';
import '../providers/settings_providers.dart';

class BookManagePage extends ConsumerStatefulWidget {
  const BookManagePage({super.key});

  @override
  ConsumerState<BookManagePage> createState() => _BookManagePageState();
}

class _BookManagePageState extends ConsumerState<BookManagePage> {
  late Future<List<Book>> _booksFuture;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  void _loadBooks() {
    _booksFuture = DatabaseService.instance.getBooks();
  }

  Future<void> _addBook() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建账本'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '账本名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      final now = DateTime.now().toIso8601String().substring(0, 19).replaceAll('T', ' ');
      final book = Book(name: result, createdAt: now);
      await DatabaseService.instance.insertBook(book);
      setState(() => _loadBooks());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('账本创建成功')));
      }
    }
  }

  Future<void> _renameBook(Book book) async {
    final controller = TextEditingController(text: book.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名账本'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '账本名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await DatabaseService.instance.updateBook(book.copyWith(name: result));
      setState(() => _loadBooks());
    }
  }

  Future<void> _deleteBook(Book book) async {
    if (book.isDefault == 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('默认账本不可删除')));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账本'),
        content: Text('确定要删除账本「${book.name}」吗？该账本下的所有记录将一并删除，此操作不可恢复！'),
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
      await DatabaseService.instance.deleteBook(book.id!);
      // 如果删除的是当前账本，切换到默认账本
      final currentId = ref.read(currentBookIdProvider);
      if (currentId == book.id) {
        final defaultBook = await DatabaseService.instance.getDefaultBook();
        if (defaultBook != null) {
          ref.read(currentBookIdProvider.notifier).setCurrentBook(defaultBook.id ?? 1);
        }
      }
      setState(() => _loadBooks());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('账本已删除')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentBookId = ref.watch(currentBookIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('账本管理'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _addBook),
        ],
      ),
      body: FutureBuilder<List<Book>>(
        future: _booksFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final books = snapshot.data!;
          return ListView.builder(
            itemCount: books.length,
            itemBuilder: (context, index) {
              final book = books[index];
              final isCurrent = book.id == currentBookId;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: Icon(
                    isCurrent ? Icons.bookmark : Icons.book_outlined,
                    color: isCurrent ? AppTheme.primaryGold : AppTheme.textHint,
                  ),
                  title: Row(
                    children: [
                      Text(book.name, style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                      if (book.isDefault == 1) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppTheme.primaryGold.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                          child: const Text('默认', style: TextStyle(fontSize: 11, color: AppTheme.primaryGold)),
                        ),
                      ],
                    ],
                  ),
                  subtitle: isCurrent ? const Text('当前使用中', style: TextStyle(color: AppTheme.primaryGold, fontSize: 12)) : null,
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'switch') {
                        ref.read(currentBookIdProvider.notifier).setCurrentBook(book.id!);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已切换到「${book.name}」')));
                      } else if (value == 'rename') {
                        _renameBook(book);
                      } else if (value == 'delete') {
                        _deleteBook(book);
                      }
                    },
                    itemBuilder: (context) => [
                      if (!isCurrent) const PopupMenuItem(value: 'switch', child: Text('切换到此账本')),
                      const PopupMenuItem(value: 'rename', child: Text('重命名')),
                      if (book.isDefault == 0) const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: AppTheme.expenseRed))),
                    ],
                  ),
                  onTap: () {
                    if (!isCurrent) {
                      ref.read(currentBookIdProvider.notifier).setCurrentBook(book.id!);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已切换到「${book.name}」')));
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
