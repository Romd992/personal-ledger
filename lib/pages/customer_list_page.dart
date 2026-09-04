import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../models/customer.dart';
import '../services/database_service.dart';
import '../providers/data_providers.dart';
import 'customer_form_page.dart';
import 'customer_detail_page.dart';

class CustomerListPage extends ConsumerStatefulWidget {
  const CustomerListPage({super.key});

  @override
  ConsumerState<CustomerListPage> createState() => _CustomerListPageState();
}

class _CustomerListPageState extends ConsumerState<CustomerListPage> {
  List<Customer> _customers = [];
  List<Customer> _filteredCustomers = [];
  bool _loading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers({bool isRefresh = false}) async {
    if (!isRefresh) setState(() => _loading = true);
    final customers = await DatabaseService.instance.getCustomers();
    if (mounted) {
      setState(() {
        _customers = customers;
        _filteredCustomers = customers;
        _loading = false;
      });
    }
  }

  void _filterCustomers(String keyword) {
    setState(() {
      if (keyword.isEmpty) {
        _filteredCustomers = _customers;
      } else {
        _filteredCustomers = _customers.where((c) =>
            c.name.contains(keyword) ||
            (c.contact?.contains(keyword) ?? false) ||
            (c.phone?.contains(keyword) ?? false)).toList();
      }
    });
  }

  Future<void> _deleteCustomer(Customer customer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除客户'),
        content: Text('确定要删除客户"${customer.name}"吗？\n\n注意：删除客户不会影响已有的收入记录。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: AppTheme.expenseRed), child: const Text('删除')),
        ],
      ),
    );
    if (confirm == true && customer.id != null) {
      await DatabaseService.instance.deleteCustomer(customer.id!);
      _loadCustomers();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('客户已删除')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 记账/删改后全局刷新信号触发：静默刷新，保证收入录入自动建档等场景客户列表实时更新
    ref.listen(refreshTriggerProvider, (previous, next) {
      if (previous != next) _loadCustomers(isRefresh: true);
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('客户台账'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerFormPage()));
            _loadCustomers();
          }),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '搜索客户名称/联系人/电话',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); _filterCustomers(''); }) : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: _filterCustomers,
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filteredCustomers.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _loadCustomers,
                      child: ListView.builder(
                        itemCount: _filteredCustomers.length,
                        itemBuilder: (context, index) {
                          final customer = _filteredCustomers[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(backgroundColor: AppTheme.primaryGold.withOpacity(0.15), child: Text(customer.name.isNotEmpty ? customer.name[0] : '?', style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold))),
                              title: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text([customer.contact, customer.phone].where((s) => s != null && s.isNotEmpty).join(' | '), style: const TextStyle(fontSize: 12, color: AppTheme.textHint)),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'edit') {
                                    await Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerFormPage(customer: customer)));
                                    _loadCustomers();
                                  } else if (v == 'delete') {
                                    _deleteCustomer(customer);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('编辑')])),
                                  PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: AppTheme.expenseRed), SizedBox(width: 8), Text('删除', style: TextStyle(color: AppTheme.expenseRed))])),
                                ],
                              ),
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailPage(customer: customer))),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: AppTheme.textHint.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(_searchController.text.isNotEmpty ? '未找到匹配的客户' : '还没有客户', style: const TextStyle(fontSize: 16, color: AppTheme.textHint)),
            const SizedBox(height: 8),
            if (_searchController.text.isEmpty)
              ElevatedButton.icon(
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerFormPage()));
                  _loadCustomers();
                },
                icon: const Icon(Icons.add),
                label: const Text('添加客户'),
              ),
          ],
        ),
      ),
    );
  }
}
