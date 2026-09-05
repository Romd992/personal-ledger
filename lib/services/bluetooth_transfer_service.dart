import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 蓝牙设备
class BluetoothDevice {
  final String name;
  final String address;
  BluetoothDevice({required this.name, required this.address});
}

/// 连接状态
class BluetoothStatus {
  final bool connected;
  final bool isServer;
  final bool searching;
  final bool transferring;
  final int progress;
  final int total;

  BluetoothStatus({
    required this.connected,
    required this.isServer,
    required this.searching,
    required this.transferring,
    required this.progress,
    required this.total,
  });

  double get progressPercent => total > 0 ? progress / total : 0.0;
  String get progressText {
    if (total <= 0) return '';
    String fmt(int bytes) {
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${fmt(progress)} / ${fmt(total)}';
  }
}

/// 蓝牙传输服务（通过 MethodChannel 调用原生安卓传统蓝牙 SPP）
class BluetoothTransferService {
  static const MethodChannel _channel = MethodChannel('com.personal.ledger/bluetooth');

  final ValueNotifier<BluetoothStatus> statusNotifier = ValueNotifier(BluetoothStatus(
    connected: false, isServer: false, searching: false,
    transferring: false, progress: 0, total: 0,
  ));

  Timer? _pollTimer;

  /// 开始轮询连接状态
  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      await refreshStatus();
    });
  }

  /// 停止轮询
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// 刷新连接状态
  Future<void> refreshStatus() async {
    try {
      final result = await _channel.invokeMethod('getConnectionStatus');
      if (result is Map) {
        statusNotifier.value = BluetoothStatus(
          connected: result['connected'] == true,
          isServer: result['isServer'] == true,
          searching: result['searching'] == true,
          transferring: result['transferring'] == true,
          progress: (result['progress'] as num?)?.toInt() ?? 0,
          total: (result['total'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (_) {}
  }

  /// 检查蓝牙是否可用
  Future<bool> isBluetoothAvailable() async {
    try {
      return await _channel.invokeMethod('isBluetoothAvailable') == true;
    } catch (_) { return false; }
  }

  /// 请求开启蓝牙
  Future<void> requestEnableBluetooth() async {
    try { await _channel.invokeMethod('requestEnableBluetooth'); } catch (_) {}
  }

  /// 获取本机蓝牙名称
  Future<String> getDeviceName() async {
    try {
      return await _channel.invokeMethod('getDeviceName') as String? ?? '未知设备';
    } catch (_) { return '未知设备'; }
  }

  /// 开始搜索附近设备
  Future<bool> startDiscovery() async {
    try {
      final ok = await _channel.invokeMethod('startDiscovery') == true;
      if (ok) {
        statusNotifier.value = BluetoothStatus(
          connected: statusNotifier.value.connected,
          isServer: statusNotifier.value.isServer,
          searching: true,
          transferring: statusNotifier.value.transferring,
          progress: statusNotifier.value.progress,
          total: statusNotifier.value.total,
        );
      }
      return ok;
    } catch (_) { return false; }
  }

  /// 停止搜索
  Future<void> cancelDiscovery() async {
    try { await _channel.invokeMethod('cancelDiscovery'); } catch (_) {}
  }

  /// 获取已发现设备列表
  Future<List<BluetoothDevice>> getDiscoveredDevices() async {
    try {
      final result = await _channel.invokeMethod('getDiscoveredDevices');
      if (result is List) {
        return result.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return BluetoothDevice(name: m['name'] as String? ?? '未知', address: m['address'] as String? ?? '');
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  /// 获取已配对设备
  Future<List<BluetoothDevice>> getPairedDevices() async {
    try {
      final result = await _channel.invokeMethod('getPairedDevices');
      if (result is List) {
        return result.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return BluetoothDevice(name: m['name'] as String? ?? '未知', address: m['address'] as String? ?? '');
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  /// 连接到指定设备（客户端模式）
  Future<bool> connectToDevice(String address) async {
    try {
      return await _channel.invokeMethod('connectToDevice', {'address': address}) == true;
    } catch (_) { return false; }
  }

  /// 启动服务端监听（等待其他设备连接）
  Future<bool> startServer() async {
    try {
      return await _channel.invokeMethod('startServer') == true;
    } catch (_) { return false; }
  }

  /// 发送文件
  Future<bool> sendFile(String filePath) async {
    try {
      return await _channel.invokeMethod('sendFile', {'filePath': filePath}) == true;
    } catch (_) { return false; }
  }

  /// 接收文件，保存到指定目录，返回保存的文件路径
  Future<String?> receiveFile(String saveDir) async {
    try {
      return await _channel.invokeMethod('receiveFile', {'saveDir': saveDir}) as String?;
    } catch (_) { return null; }
  }

  /// 断开连接
  Future<void> disconnect() async {
    try { await _channel.invokeMethod('disconnect'); } catch (_) {}
    statusNotifier.value = BluetoothStatus(
      connected: false, isServer: false, searching: false,
      transferring: false, progress: 0, total: 0,
    );
  }

  /// 释放资源
  void dispose() {
    stopPolling();
    statusNotifier.dispose();
  }
}
