import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'file_search_service.dart';

/// 平台文件服务 - 统一处理Windows和Android的文件保存/打开/选择
class PlatformFileService {
  /// 是否为Windows桌面平台
  static bool get isWindows => !kIsWeb && Platform.isWindows;

  /// 是否为Android平台
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// 保存文件到用户选择的位置
  /// - Windows: 弹出"另存为"对话框
  /// - Android: 弹出系统分享菜单
  /// 返回保存后的文件路径（Windows）或null（Android）
  static Future<String?> saveFile({
    required String fileName,
    required List<int> bytes,
    String? dialogTitle,
  }) async {
    if (isWindows) {
      // Windows: 使用FilePicker的saveFile方法
      try {
        final outputPath = await FilePicker.platform.saveFile(
          dialogTitle: dialogTitle ?? '保存文件',
          fileName: fileName,
          type: FileType.any,
        );
        if (outputPath != null) {
          await File(outputPath).writeAsBytes(bytes, flush: true);
          return outputPath;
        }
        return null;
      } catch (e) {
        // 如果saveFile不可用，降级到保存到文档目录
        final dir = await _getWindowsSaveDir();
        final path = '${dir.path}/$fileName';
        await File(path).writeAsBytes(bytes, flush: true);
        return path;
      }
    } else {
      // Android: 使用系统分享
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/$fileName';
      await File(path).writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(path, name: fileName)],
        text: dialogTitle ?? '文件已生成',
      );
      return null;
    }
  }

  /// 保存文本文件
  static Future<String?> saveTextFile({
    required String fileName,
    required String content,
    String? dialogTitle,
  }) async {
    return saveFile(
      fileName: fileName,
      bytes: utf8.encode(content),
      dialogTitle: dialogTitle,
    );
  }

  /// 统一的备份根目录（用户可见、文件管理器可直接访问）
  /// - Android：外部存储应用目录下的「简帐备份」，无需敏感权限、系统文件管理器可定位
  /// - Windows：我的文档/简帐备份
  /// - 其他：应用文档目录/简帐备份
  static Future<Directory> getBackupDirectory() async {
    Directory base;
    if (isAndroid) {
      // /storage/emulated/0/Android/data/<包名>/files —— 外部可见、免存储权限
      final ext = await getExternalStorageDirectory();
      base = ext ?? await getApplicationDocumentsDirectory();
    } else if (isWindows) {
      final home = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '.';
      base = Directory('$home/Documents');
    } else {
      base = await getApplicationDocumentsDirectory();
    }
    final target = Directory('${base.path}/简帐备份');
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    return target;
  }

  /// 启动时调用：把旧目录「个人记账备份」中的文件迁移到新目录「简帐备份」
  static Future<void> migrateOldBackupDir() async {
    try {
      Directory base;
      if (isAndroid) {
        final ext = await getExternalStorageDirectory();
        base = ext ?? await getApplicationDocumentsDirectory();
      } else if (isWindows) {
        final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
        base = Directory('$home/Documents');
      } else {
        base = await getApplicationDocumentsDirectory();
      }
      final oldDir = Directory('${base.path}/个人记账备份');
      final newDir = await getBackupDirectory();
      if (await oldDir.exists()) {
        await for (final entity in oldDir.list()) {
          if (entity is File) {
            final newPath = '${newDir.path}/${entity.uri.pathSegments.last}';
            if (!File(newPath).existsSync()) {
              await entity.copy(newPath);
            }
          }
        }
      }
    } catch (_) {
      // 迁移失败不影响使用
    }
  }

  /// 打开文件夹（在文件管理器中显示）
  static Future<String?> openFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    if (isWindows) {
      // Windows: 用explorer打开文件夹
      await Process.run('explorer.exe', [folderPath]);
      return null;
    } else if (isAndroid) {
      // Android: 用原生 Intent 调起系统文件管理器（修复 open_filex 打不开目录的问题）
      final result = await FileSearchService.openFolder(folderPath);
      return result == 'ok' ? null : result;
    }
    return null;
  }

  /// 获取Windows下的默认保存目录（文档目录下的"个人记账导出"文件夹）
  static Future<Directory> _getWindowsSaveDir() async {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    final dir = Directory('$home/Documents/个人记账导出');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 选择文件（用于导入）
  static Future<File?> pickFile({
    List<String>? allowedExtensions,
    String? dialogTitle,
    FileType type = FileType.any,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
      dialogTitle: dialogTitle,
    );
    if (result == null ||
        result.files.isEmpty ||
        result.files.single.path == null) {
      return null;
    }
    return File(result.files.single.path!);
  }

  /// 选择图片（用于凭证图片）
  static Future<File?> pickImage({String? dialogTitle}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      dialogTitle: dialogTitle ?? '选择凭证图片',
    );
    if (result == null ||
        result.files.isEmpty ||
        result.files.single.path == null) {
      return null;
    }
    return File(result.files.single.path!);
  }

  /// 选择多张图片
  static Future<List<File>> pickMultipleImages({String? dialogTitle}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      dialogTitle: dialogTitle ?? '选择凭证图片（可多选）',
    );
    if (result == null || result.files.isEmpty) {
      return [];
    }
    return result.files
        .where((f) => f.path != null)
        .map((f) => File(f.path!))
        .toList();
  }
}
