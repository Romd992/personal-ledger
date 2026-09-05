import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/data_migration_service.dart';
import '../services/file_search_service.dart';
import '../providers/data_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 导入备份页面：自动搜索手机中的备份文件，点选即可导入
class ImportBackupPage extends ConsumerStatefulWidget {
  const ImportBackupPage({super.key});

  @override
  ConsumerState<ImportBackupPage> createState() => _ImportBackupPageState();
}

class _ImportBackupPageState extends ConsumerState<ImportBackupPage> {
  bool _searching = true;
  List<FoundBackupFile> _files = [];
  bool _importing = false;
  bool _showWechatTip = true;

  @override
  void initState() {
    super.initState();
    _doSearch();
  }

  /// 自动搜索手机中的备份文件
  Future<void> _doSearch() async {
    setState(() => _searching = true);
    final files = await FileSearchService.searchBackupFiles();
    if (mounted) {
      setState(() {
        _files = files;
        _searching = false;
      });
    }
  }

  /// 将 content:// URI 的文件读取字节并写入临时文件，返回临时文件路径
  Future<String> _ensureLocalFile(FoundBackupFile f) async {
    if (f.uri.startsWith('file://')) {
      return Uri.parse(f.uri).toFilePath();
    }
    // content:// URI：读取字节写入临时文件
    final bytes = await FileSearchService.readFileBytes(f.uri);
    if (bytes == null) throw Exception('无法读取文件内容');
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/import_${DateTime.now().millisecondsSinceEpoch}_${f.name}');
    await tempFile.writeAsBytes(bytes);
    return tempFile.path;
  }

  /// 点选文件后执行导入
  Future<void> _importFile(FoundBackupFile f) async {
    // 确认对话框
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认导入'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('文件：${f.name}', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            Text('大小：${f.sizeText}  时间：${f.dateText}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            const Text('⚠️ 导入将覆盖当前所有数据，建议先导出当前数据作为备份！', style: TextStyle(fontSize: 12, color: Colors.red)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
            child: const Text('确认导入'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    // 加密备份需要输入密码
    String? password;
    if (f.isEncrypted) {
      final pwdController = TextEditingController();
      final pwdResult = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('输入加密密码'),
          content: TextField(
            controller: pwdController,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '密码',
              border: OutlineInputBorder(),
              hintText: '导出备份时设置的密码',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('取消')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, pwdController.text),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      if (pwdResult == null) return;
      password = pwdResult;
    }

    setState(() => _importing = true);
    try {
      final localPath = await _ensureLocalFile(f);

      if (f.isEncrypted) {
        // .ledger 加密备份
        final db = await DatabaseService.instance.database;
        final result = await DataMigrationService.importFullBackup(
          ledgerPath: localPath,
          password: password!,
          db: db,
        );
        if (mounted) {
          _refreshData();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入成功！恢复了 ${result['tablesRestored']} 张表，${result['rowsRestored']} 条记录')),
          );
          Navigator.pop(context, true);
        }
      } else if (f.isJson) {
        // JSON 备份
        final content = await File(localPath).readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final count = await DatabaseService.instance.importAllData(data, clearExisting: true);
        if (mounted) {
          _refreshData();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入成功，共导入 $count 条数据')),
          );
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('不支持的文件格式，请选择 .ledger 或 .json 备份文件')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败：$e'), backgroundColor: AppTheme.expenseRed),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// 导入后刷新所有数据缓存
  void _refreshData() {
    ref.invalidate(incomesProvider);
    ref.invalidate(expensesProvider);
    ref.invalidate(expenseTypesProvider);
    ref.read(refreshTriggerProvider.notifier).state++;
  }

  /// 手动选择文件（兜底）
  Future<void> _pickManual() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ledger', 'json'],
      );
      if (result == null || result.files.isEmpty || result.files.single.path == null) return;
      final path = result.files.single.path!;
      final file = File(path);
      final found = FoundBackupFile(
        name: file.uri.pathSegments.last,
        size: await file.length(),
        dateModified: (await file.lastModified()).millisecondsSinceEpoch ~/ 1000,
        uri: Uri.file(path).toString(),
        source: 'Manual',
      );
      _importFile(found);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择文件失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入备份'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新搜索',
            onPressed: _searching ? null : _doSearch,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // 微信文件引导提示
              if (_showWechatTip)
                Container(
                  width: double.infinity,
                  color: const Color(0xFFFFF8E1),
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, size: 18, color: Colors.orange),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '如果备份文件来自微信/QQ，请先在微信里点开文件 → 右上角「…」→「保存到手机」，保存后文件会出现在下方列表中。',
                          style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _showWechatTip = false),
                        child: const Icon(Icons.close, size: 16, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              // 搜索结果列表
              Expanded(
                child: _searching
                    ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        CircularProgressIndicator(color: AppTheme.primaryGold),
                        SizedBox(height: 12),
                        Text('正在搜索手机中的备份文件…', style: TextStyle(color: Colors.grey)),
                      ]))
                    : _files.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _files.length,
                            itemBuilder: (context, index) => _buildFileCard(_files[index]),
                          ),
              ),
              // 底部手动选择按钮
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _importing ? null : _pickManual,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('手动选择其他文件'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryGold,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // 导入中遮罩
          if (_importing)
            Container(
              color: Colors.black54,
              child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 12),
                Text('正在导入数据…', style: TextStyle(color: Colors.white)),
              ])),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.folder_off_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('未找到备份文件', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            '请确认文件已保存到手机（微信/QQ接收的文件需先点「保存到手机」），或点击下方按钮手动选择。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.5),
          ),
        ]),
      ),
    );
  }

  Widget _buildFileCard(FoundBackupFile f) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: _importing ? null : () => _importFile(f),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: f.isEncrypted
                      ? AppTheme.primaryGold.withOpacity(0.12)
                      : Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  f.isEncrypted ? Icons.lock_outline : Icons.description_outlined,
                  color: f.isEncrypted ? AppTheme.primaryGold : Colors.blue,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.name,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(f.sizeText, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(width: 10),
                        Text(f.dateText, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (f.isEncrypted)
                          _tag('加密备份', AppTheme.primaryGold)
                        else
                          _tag('JSON备份', Colors.blue),
                        const SizedBox(width: 6),
                        _tag(f.source == 'AppBackup' ? '本应用备份' : f.source == 'MediaStore' ? '手机存储' : '手动选择', Colors.grey),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}
