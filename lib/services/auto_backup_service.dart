import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';
import '../services/platform_file_service.dart';

class AutoBackupService {
  static const String _lastBackupKey = 'last_backup_time';

  // 执行自动备份
  static Future<bool> executeBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final autoBackup = prefs.getBool('auto_backup') ?? true;
      if (!autoBackup) return false;

      // 导出数据
      final data = await DatabaseService.instance.exportAllData();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

      // 获取统一的外部可见备份目录
      final backupDir = await PlatformFileService.getBackupDirectory();

      // 生成文件名
      final now = DateTime.now();
      final fileName = 'auto_${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}_${now.hour.toString().padLeft(2,'0')}${now.minute.toString().padLeft(2,'0')}${now.second.toString().padLeft(2,'0')}.json';
      final file = File('${backupDir.path}/$fileName');
      await file.writeAsString(jsonStr);

      // 记录最后备份时间
      await prefs.setString(_lastBackupKey, now.toIso8601String());

      // 清理超过容量上限的旧备份
      await _cleanupOldBackups(backupDir, prefs);

      return true;
    } catch (e) {
      // 自动备份失败不影响主流程
      return false;
    }
  }

  // 清理超过容量上限的旧备份
  static Future<void> _cleanupOldBackups(Directory backupDir, SharedPreferences prefs) async {
    try {
      final limitMb = prefs.getInt('backup_limit_mb') ?? 1024;
      final limitBytes = limitMb * 1024 * 1024;

      final files = backupDir.listSync().whereType<File>().toList();
      // 按修改时间排序（最旧的在前）
      files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));

      // 计算总大小
      int totalSize = 0;
      for (var f in files) {
        totalSize += await f.length();
      }

      // 如果超过上限，删除最旧的备份
      while (totalSize > limitBytes && files.isNotEmpty) {
        final oldest = files.removeAt(0);
        final size = await oldest.length();
        await oldest.delete();
        totalSize -= size;
      }
    } catch (_) {}
  }

  // 获取最后备份时间
  static Future<DateTime?> getLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(_lastBackupKey);
    if (timeStr == null) return null;
    return DateTime.tryParse(timeStr);
  }

  // 获取备份文件列表
  static Future<List<File>> getBackupFiles() async {
    final backupDir = await PlatformFileService.getBackupDirectory();
    final files = backupDir.listSync().whereType<File>().toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  // 获取备份目录路径
  static Future<String> getBackupDirPath() async {
    final dir = await PlatformFileService.getBackupDirectory();
    return dir.path;
  }

  // 手动备份（返回文件路径）
  static Future<String?> manualBackup() async {
    try {
      final data = await DatabaseService.instance.exportAllData();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

      final backupDir = await PlatformFileService.getBackupDirectory();

      final now = DateTime.now();
      final fileName = 'manual_${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}_${now.hour.toString().padLeft(2,'0')}${now.minute.toString().padLeft(2,'0')}.json';
      final file = File('${backupDir.path}/$fileName');
      await file.writeAsString(jsonStr);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastBackupKey, now.toIso8601String());

      await _cleanupOldBackups(backupDir, prefs);

      return file.path;
    } catch (e) {
      return null;
    }
  }
}
