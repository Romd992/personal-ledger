import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_theme.dart';
import '../services/bluetooth_transfer_service.dart';
import '../services/platform_file_service.dart';
import 'import_backup_page.dart';

class BluetoothTransferPage extends StatefulWidget {
  const BluetoothTransferPage({super.key});

  @override
  State<BluetoothTransferPage> createState() => _BluetoothTransferPageState();
}

class _BluetoothTransferPageState extends State<BluetoothTransferPage> {
  final BluetoothTransferService _service = BluetoothTransferService();
  List<BluetoothDevice> _pairedDevices = [];
  List<BluetoothDevice> _discoveredDevices = [];
  String? _connectedDeviceName;
  String? _selectedFilePath;
  String? _receivedFilePath;
  String _status = '请先开启蓝牙';
  int _mode = 0; // 0: 未选择, 1: 发送, 2: 接收
  bool _btAvailable = false;

  @override
  void initState() {
    super.initState();
    _service.startPolling();
    _service.statusNotifier.addListener(_onStatusChanged);
    _checkBluetooth();
  }

  @override
  void dispose() {
    _service.statusNotifier.removeListener(_onStatusChanged);
    _service.disconnect();
    _service.dispose();
    super.dispose();
  }

  void _onStatusChanged() {
    if (!mounted) return;
    final s = _service.statusNotifier.value;
    setState(() {});
    if (s.connected && _connectedDeviceName == null) {
      _status = _mode == 2 ? '对方已连接，可以接收文件' : '已连接，可以发送文件';
    }
    if (!s.connected && _connectedDeviceName != null && !s.searching) {
      _connectedDeviceName = null;
      _status = '已断开连接';
    }
  }

  Future<void> _checkBluetooth() async {
    final available = await _service.isBluetoothAvailable();
    setState(() {
      _btAvailable = available;
      _status = available ? '蓝牙已开启' : '蓝牙未开启';
    });
    if (available) {
      _loadPairedDevices();
    }
  }

  Future<void> _loadPairedDevices() async {
    final devices = await _service.getPairedDevices();
    setState(() => _pairedDevices = devices);
  }

  Future<void> _startDiscovery() async {
    setState(() {
      _discoveredDevices = [];
      _status = '正在搜索附近设备…';
    });
    final ok = await _service.startDiscovery();
    if (!ok) {
      setState(() => _status = '搜索失败，请检查蓝牙权限');
      return;
    }
    // 搜索10秒后获取结果
    await Future.delayed(const Duration(seconds: 10));
    final devices = await _service.getDiscoveredDevices();
    if (mounted) {
      setState(() {
        _discoveredDevices = devices;
        _status = '搜索完成，发现 ${devices.length} 台设备';
      });
    }
  }

  Future<void> _connectDevice(BluetoothDevice device) async {
    setState(() => _status = '正在连接 ${device.name}…');
    final ok = await _service.connectToDevice(device.address);
    if (ok) {
      setState(() {
        _connectedDeviceName = device.name;
        _status = '已连接到 ${device.name}，请选择要发送的文件';
      });
    } else {
      setState(() => _status = '连接失败，请确保对方已开启接收模式');
    }
  }

  Future<void> _startServer() async {
    setState(() => _status = '正在等待对方连接…');
    final ok = await _service.startServer();
    if (!ok) {
      setState(() => _status = '启动失败，请检查蓝牙权限');
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ledger', 'json'],
    );
    if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
      setState(() {
        _selectedFilePath = result.files.single.path;
        _status = '已选择文件：${result.files.single.name}';
      });
    }
  }

  Future<void> _sendFile() async {
    if (_selectedFilePath == null) return;
    setState(() => _status = '正在发送文件…');
    final ok = await _service.sendFile(_selectedFilePath!);
    if (ok) {
      setState(() => _status = '文件发送成功！');
    } else {
      setState(() => _status = '发送失败，连接可能已断开');
    }
  }

  Future<void> _receiveFile() async {
    final backupDir = await PlatformFileService.getBackupDirectory();
    setState(() => _status = '正在接收文件…');
    final path = await _service.receiveFile(backupDir.path);
    if (path != null) {
      setState(() {
        _receivedFilePath = path;
        _status = '接收成功：${File(path).uri.pathSegments.last}';
      });
    } else {
      setState(() => _status = '接收失败，连接可能已断开');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _service.statusNotifier.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('蓝牙互传'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 蓝牙状态卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        s.connected ? Icons.bluetooth_connected : (_btAvailable ? Icons.bluetooth : Icons.bluetooth_disabled),
                        color: s.connected ? Colors.blue : (_btAvailable ? AppTheme.primaryGold : Colors.grey),
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.connected ? '已连接：$_connectedDeviceName' : (_btAvailable ? '蓝牙已开启' : '蓝牙未开启'),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(_status, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                      if (!_btAvailable)
                        TextButton(
                          onPressed: () async {
                            await _service.requestEnableBluetooth();
                            await Future.delayed(const Duration(seconds: 2));
                            _checkBluetooth();
                          },
                          child: const Text('开启蓝牙'),
                        ),
                    ],
                  ),
                  // 传输进度
                  if (s.transferring) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: s.progressPercent,
                      backgroundColor: Colors.grey[200],
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryGold),
                    ),
                    const SizedBox(height: 4),
                    Text(s.progressText, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 模式选择
          if (_mode == 0) ...[
            const Text('选择操作模式', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ModeCard(
                    icon: Icons.upload_file,
                    title: '发送文件',
                    subtitle: '搜索设备并发送备份',
                    color: AppTheme.primaryGold,
                    onTap: _btAvailable ? () => setState(() => _mode = 1) : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ModeCard(
                    icon: Icons.file_download,
                    title: '接收文件',
                    subtitle: '等待对方连接并接收',
                    color: Colors.blue,
                    onTap: _btAvailable ? () => setState(() => _mode = 2) : null,
                  ),
                ),
              ],
            ),
          ],

          // 发送模式
          if (_mode == 1) ...[
            _buildModeHeader('发送文件', Icons.upload_file, AppTheme.primaryGold),
            // 已配对设备
            if (_pairedDevices.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('已配对设备', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
              const SizedBox(height: 8),
              ..._pairedDevices.map((d) => _buildDeviceTile(d, s.connected)),
            ],
            const SizedBox(height: 12),
            // 搜索按钮
            ElevatedButton.icon(
              onPressed: s.searching ? null : _startDiscovery,
              icon: s.searching
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search),
              label: Text(s.searching ? '搜索中…' : '搜索附近设备'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGold,
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
            // 搜索到的设备
            if (_discoveredDevices.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('附近设备', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
              const SizedBox(height: 8),
              ..._discoveredDevices.map((d) => _buildDeviceTile(d, s.connected)),
            ],
            const SizedBox(height: 16),
            // 选择文件和发送
            if (s.connected) ...[
              Card(
                color: Colors.green[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (_selectedFilePath != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.insert_drive_file, color: Colors.green, size: 20),
                              const SizedBox(width: 8),
                              Expanded(child: Text(File(_selectedFilePath!).uri.pathSegments.last, style: const TextStyle(fontSize: 13))),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickFile,
                              icon: const Icon(Icons.folder_open),
                              label: const Text('选择文件'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: (_selectedFilePath != null && !s.transferring) ? _sendFile : null,
                              icon: const Icon(Icons.send),
                              label: Text(s.transferring ? '发送中…' : '发送'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],

          // 接收模式
          if (_mode == 2) ...[
            _buildModeHeader('接收文件', Icons.file_download, Colors.blue),
            const SizedBox(height: 16),
            if (!s.connected && !s.isServer)
              ElevatedButton.icon(
                onPressed: _startServer,
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('启动接收（等待对方连接）'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            if (s.isServer && !s.connected)
              Card(
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(color: Colors.blue)),
                      const SizedBox(height: 12),
                      const Text('正在等待对方连接…', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      FutureBuilder<String>(
                        future: _service.getDeviceName(),
                        builder: (context, snap) => Text('本机名称：${snap.data ?? "未知"}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ),
                      const SizedBox(height: 8),
                      const Text('请在对方设备上搜索并连接本机', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            if (s.connected) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: !s.transferring ? _receiveFile : null,
                icon: const Icon(Icons.download),
                label: Text(s.transferring ? '接收中…' : '开始接收文件'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ],
            // 接收完成
            if (_receivedFilePath != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.green[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.check_circle, color: Colors.green, size: 20),
                          SizedBox(width: 8),
                          Text('接收成功', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('文件：${File(_receivedFilePath!).uri.pathSegments.last}', style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportBackupPage()));
                        },
                        icon: const Icon(Icons.import_export),
                        label: const Text('立即导入此备份'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],

          const SizedBox(height: 24),
          // 使用说明
          Card(
            color: Colors.grey[50],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('使用说明', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('1. 两台设备都打开「蓝牙互传」页面，并开启蓝牙', style: TextStyle(fontSize: 12, height: 1.5)),
                  Text('2. 接收方点击「启动接收」，等待对方连接', style: TextStyle(fontSize: 12, height: 1.5)),
                  Text('3. 发送方点击「搜索附近设备」，找到接收方后点击连接', style: TextStyle(fontSize: 12, height: 1.5)),
                  Text('4. 连接成功后，发送方选择 .ledger 备份文件并发送', style: TextStyle(fontSize: 12, height: 1.5)),
                  Text('5. 接收方点击「开始接收文件」，接收完成后可直接导入', style: TextStyle(fontSize: 12, height: 1.5)),
                  Text('6. 传输采用蓝牙 SPP 直连，数据不经过任何服务器', style: TextStyle(fontSize: 12, height: 1.5)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 返回模式选择
          if (_mode != 0)
            TextButton.icon(
              onPressed: () async {
                await _service.disconnect();
                setState(() {
                  _mode = 0;
                  _connectedDeviceName = null;
                  _selectedFilePath = null;
                  _receivedFilePath = null;
                  _discoveredDevices = [];
                  _status = '请选择操作模式';
                });
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text('返回模式选择'),
            ),
        ],
      ),
    );
  }

  Widget _buildModeHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildDeviceTile(BluetoothDevice device, bool connected) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.phone_android, color: AppTheme.primaryGold),
        title: Text(device.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(device.address, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        trailing: connected
            ? const Icon(Icons.check_circle, color: Colors.green)
            : ElevatedButton(
                onPressed: () => _connectDevice(device),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGold,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: const Text('连接', style: TextStyle(fontSize: 12)),
              ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: onTap != null ? color.withOpacity(0.08) : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: onTap != null ? color.withOpacity(0.3) : Colors.grey[300]!),
        ),
        child: Column(
          children: [
            Icon(icon, color: onTap != null ? color : Colors.grey, size: 36),
            const SizedBox(height: 10),
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: onTap != null ? Colors.black87 : Colors.grey)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
