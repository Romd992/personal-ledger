import 'dart:typed_data';
import 'package:flutter/services.dart';

/// 搜索到的备份文件
class FoundBackupFile {
  final String name;
  final int size;
  final int dateModified; // 秒级时间戳
  final String uri; // content:// 或 file://
  final String source; // MediaStore / AppBackup

  FoundBackupFile({
    required this.name,
    required this.size,
    required this.dateModified,
    required this.uri,
    required this.source,
  });

  /// 是否为加密备份（.ledger）
  bool get isEncrypted => name.toLowerCase().endsWith('.ledger');

  /// 是否为 JSON 备份
  bool get isJson => name.toLowerCase().endsWith('.json');

  String get sizeText {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get dateText {
    final dt = DateTime.fromMillisecondsSinceEpoch(dateModified * 1000);
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d $h:$min';
  }
}

/// 文件搜索服务（通过 MethodChannel 调用原生安卓 MediaStore）
class FileSearchService {
  static const MethodChannel _channel =
      MethodChannel('com.personal.ledger/filesearch');

  /// 搜索手机中所有相关备份文件
  static Future<List<FoundBackupFile>> searchBackupFiles() async {
    try {
      final result = await _channel.invokeMethod('searchBackupFiles', {
        'keywords': [
          'ledger',
          '简帐备份',
          '个人记账备份',
          'auto_',
          '记账备份',
        ],
      });
      if (result is List) {
        return result.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return FoundBackupFile(
            name: m['name'] as String? ?? '未知文件',
            size: (m['size'] as num?)?.toInt() ?? 0,
            dateModified: (m['dateModified'] as num?)?.toInt() ?? 0,
            uri: m['uri'] as String? ?? '',
            source: m['source'] as String? ?? 'unknown',
          );
        }).toList();
      }
    } catch (_) {
      // 原生通道不可用（如桌面端），返回空
    }
    return [];
  }

  /// 读取选中文件的字节内容
  static Future<Uint8List?> readFileBytes(String uri) async {
    try {
      final result = await _channel.invokeMethod('readFileBytes', {'uri': uri});
      if (result is Uint8List) return result;
      if (result is List<int>) return Uint8List.fromList(result);
    } catch (_) {}
    return null;
  }

  /// 用系统文件管理器打开指定目录
  static Future<String> openFolder(String path) async {
    try {
      final result = await _channel.invokeMethod('openFolder', {'path': path});
      return result as String? ?? 'error';
    } catch (e) {
      return 'error: $e';
    }
  }
}
