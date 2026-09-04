import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../providers/data_providers.dart';

class WifiTransferPage extends ConsumerStatefulWidget {
  const WifiTransferPage({super.key});

  @override
  ConsumerState<WifiTransferPage> createState() => _WifiTransferPageState();
}

class _WifiTransferPageState extends ConsumerState<WifiTransferPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 发送端状态
  String? _serverIp;
  int _serverPort = 8888;
  HttpServer? _server;
  bool _serverRunning = false;
  String _serverStatus = '未启动';
  int _connectedClients = 0;
  // 按客户端IP去重统计，避免同一设备重复下载被重复计数
  final Set<String> _clientIps = {};

  // 接收端状态
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(text: '8888');
  bool _receiving = false;
  String _receiveStatus = '';
  Map<String, dynamic>? _receivedData;
  double _downloadProgress = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _getWifiIp();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _stopServer();
    super.dispose();
  }

  Future<void> _getWifiIp() async {
    try {
      final info = NetworkInfo();
      final ip = await info.getWifiIP();
      if (mounted) setState(() => _serverIp = ip);
    } catch (e) {
      if (mounted) setState(() => _serverStatus = '获取IP失败: $e');
    }
  }

  // ==================== 发送端 ====================

  Future<void> _startServer() async {
    if (_serverIp == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法获取WiFi IP，请确认已连接WiFi')));
      return;
    }
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _serverPort);
      setState(() {
        _serverRunning = true;
        _serverStatus = '等待接收端连接...';
        _connectedClients = 0;
        _clientIps.clear();
      });

      _server!.listen((HttpRequest request) async {
        if (request.method == 'GET' && request.uri.path == '/data') {
          final clientIp = request.connectionInfo?.remoteAddress.address ?? '';
          final isNewClient = clientIp.isEmpty || _clientIps.add(clientIp);
          setState(() {
            if (isNewClient) _connectedClients = _clientIps.length;
            _serverStatus = '正在发送数据...';
          });

          final data = await DatabaseService.instance.exportAllData();
          final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
          final bytes = utf8.encode(jsonStr);

          request.response.headers.contentType = ContentType.json;
          request.response.headers.contentLength = bytes.length;
          request.response.add(bytes);
          await request.response.close();

          if (mounted) setState(() => _serverStatus = '数据已发送给第$_connectedClients台设备，继续等待...');
        } else if (request.method == 'GET' && request.uri.path == '/ping') {
          request.response.statusCode = 200;
          request.response.write('ok');
          await request.response.close();
        } else {
          request.response.statusCode = 404;
          await request.response.close();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _serverStatus = '启动失败: $e');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('服务器启动失败: $e'), backgroundColor: AppTheme.expenseRed));
      }
    }
  }

  Future<void> _stopServer() async {
    await _server?.close(force: true);
    _server = null;
    if (mounted) setState(() {
      _serverRunning = false;
      _serverStatus = '已停止';
    });
  }

  // ==================== 接收端 ====================

  Future<void> _receiveData() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 8888;

    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入发送端IP地址')));
      return;
    }

    setState(() {
      _receiving = true;
      _receiveStatus = '正在连接发送端...';
      _downloadProgress = 0;
      _receivedData = null;
    });

    try {
      // 先ping测试连接
      final pingClient = HttpClient();
      pingClient.connectionTimeout = const Duration(seconds: 5);
      final pingReq = await pingClient.get(ip, port, '/ping');
      final pingResp = await pingReq.close();
      if (pingResp.statusCode != 200) {
        throw '连接失败，请确认IP和端口正确';
      }
      pingClient.close();

      setState(() {
        _receiveStatus = '连接成功，正在下载数据...';
        _downloadProgress = 0.3;
      });

      // 下载数据
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      final request = await client.get(ip, port, '/data');
      final response = await request.close();

      if (response.statusCode != 200) {
        throw '下载失败，状态码: ${response.statusCode}';
      }

      final bytes = await response.fold<List<int>>([], (prev, element) => prev..addAll(element));
      final jsonStr = utf8.decode(bytes);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      setState(() {
        _receivedData = data;
        _receiveStatus = '下载完成，请确认后导入';
        _downloadProgress = 1.0;
      });

      client.close();
    } catch (e) {
      if (mounted) {
        setState(() => _receiveStatus = '失败: $e');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('接收失败: $e'), backgroundColor: AppTheme.expenseRed));
      }
    } finally {
      if (mounted) setState(() => _receiving = false);
    }
  }

  Future<void> _importReceivedData() async {
    if (_receivedData == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认导入数据'),
        content: const Text('导入将覆盖当前所有数据，是否继续？\n\n建议先在发送端确认数据完整。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: AppTheme.expenseRed), child: const Text('确认导入')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _receiving = true);
    try {
      final count = await DatabaseService.instance.importAllData(_receivedData!, clearExisting: true);
      // 导入会整体覆盖数据库，必须通知首页/列表/税务/统计/客户等所有缓存页面刷新，否则仍显示旧数据
      ref.invalidate(incomesProvider);
      ref.invalidate(expensesProvider);
      ref.invalidate(expenseTypesProvider);
      ref.read(refreshTriggerProvider.notifier).state++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入成功，共 $count 条数据')));
        setState(() {
          _receivedData = null;
          _receiveStatus = '';
          _downloadProgress = 0;
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e'), backgroundColor: AppTheme.expenseRed));
    } finally {
      if (mounted) setState(() => _receiving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi直传'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [Tab(text: '发送数据'), Tab(text: '接收数据')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildSendTab(), _buildReceiveTab()],
      ),
    );
  }

  Widget _buildSendTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('使用说明', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _step(1, '确保两台设备连接同一个WiFi'),
              _step(2, '在发送端点击"启动服务器"'),
              _step(3, '在接收端输入显示的IP地址和端口'),
              _step(4, '接收端点击"连接并下载"，确认后导入'),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                const Icon(Icons.wifi, color: AppTheme.primaryGold),
                const SizedBox(width: 8),
                const Text('当前WiFi IP', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                const Spacer(),
                Text(_serverIp ?? '获取中...', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryGold)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.portable_wifi_off, color: AppTheme.textHint),
                const SizedBox(width: 8),
                const Text('端口', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                const Spacer(),
                Text('$_serverPort', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ]),
              const Divider(height: 24),
              if (_serverRunning) ...[
                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppTheme.incomeGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Row(children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.incomeGreen)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_serverStatus, style: const TextStyle(fontSize: 13, color: AppTheme.incomeGreen))),
                ])),
                const SizedBox(height: 8),
                Text('已连接设备: $_connectedClients 台', style: const TextStyle(fontSize: 12, color: AppTheme.textHint)),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _stopServer, icon: const Icon(Icons.stop), label: const Text('停止服务器'), style: OutlinedButton.styleFrom(foregroundColor: AppTheme.expenseRed, side: const BorderSide(color: AppTheme.expenseRed)))),
              ] else ...[
                SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _startServer, icon: const Icon(Icons.play_arrow), label: const Text('启动服务器'), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold, foregroundColor: Colors.white))),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 16),
        if (_serverRunning && _serverIp != null)
          Card(
            color: AppTheme.bgWarm,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                const Text('接收端请输入以下信息', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryGold)),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('IP: ', style: TextStyle(fontSize: 16)),
                  Text(_serverIp!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryGold)),
                ]),
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('端口: ', style: TextStyle(fontSize: 16)),
                  Text('$_serverPort', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryGold)),
                ]),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _buildReceiveTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('连接信息', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: _ipController,
                decoration: const InputDecoration(labelText: '发送端IP地址', hintText: '如：192.168.1.100', prefixIcon: Icon(Icons.wifi), border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _portController,
                decoration: const InputDecoration(labelText: '端口号', hintText: '默认8888', prefixIcon: Icon(Icons.settings_ethernet), border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                onPressed: _receiving ? null : _receiveData,
                icon: _receiving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.download),
                label: Text(_receiving ? '连接中...' : '连接并下载'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold, foregroundColor: Colors.white),
              )),
            ]),
          ),
        ),
        if (_receiveStatus.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Row(children: [
                  Icon(_downloadProgress == 1.0 ? Icons.check_circle : Icons.info, color: _downloadProgress == 1.0 ? AppTheme.incomeGreen : AppTheme.primaryGold),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_receiveStatus, style: const TextStyle(fontSize: 14))),
                ]),
                if (_receiving && _downloadProgress > 0 && _downloadProgress < 1) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _downloadProgress, backgroundColor: AppTheme.divider, valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryGold)),
                ],
              ]),
            ),
          ),
        ],
        if (_receivedData != null) ...[
          const SizedBox(height: 16),
          Card(
            color: AppTheme.incomeGreen.withOpacity(0.05),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('下载完成 - 数据摘要', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.incomeGreen)),
                const SizedBox(height: 12),
                _dataRow('收入记录', '${(_receivedData!['stats'] as Map)['incomeCount']} 笔'),
                _dataRow('支出记录', '${(_receivedData!['stats'] as Map)['expenseCount']} 笔'),
                _dataRow('客户档案', '${(_receivedData!['stats'] as Map)['customerCount']} 个'),
                _dataRow('导出版本', _receivedData!['version'] as String),
                _dataRow('导出时间', (_receivedData!['exportTime'] as String).substring(0, 19).replaceAll('T', ' ')),
                const Divider(height: 24),
                const Text('确认数据无误后点击下方按钮导入，导入将覆盖当前所有数据。', style: TextStyle(fontSize: 12, color: AppTheme.textHint)),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _receiving ? null : _importReceivedData, icon: const Icon(Icons.check), label: const Text('确认导入数据'), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.incomeGreen, foregroundColor: Colors.white))),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('注意事项', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _note('两台设备必须连接同一个WiFi网络'),
              _note('发送端需要保持APP在前台运行'),
              _note('导入数据会覆盖当前所有数据，请谨慎操作'),
              _note('建议先备份当前数据再导入'),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _step(int num, String text) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [CircleAvatar(radius: 12, backgroundColor: AppTheme.primaryGold, child: Text('$num', style: const TextStyle(fontSize: 12, color: Colors.white))), const SizedBox(width: 10), Expanded(child: Text(text, style: const TextStyle(fontSize: 13)))]));

  Widget _dataRow(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)), Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))]));

  Widget _note(String text) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [const Icon(Icons.info_outline, size: 14, color: AppTheme.textHint), const SizedBox(width: 6), Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: AppTheme.textHint)))]));
}
