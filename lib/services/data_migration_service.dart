import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'platform_file_service.dart';

/// 数据迁移服务 - 一键打包/恢复全部数据
/// 备份文件采用真正的 AES-256-CBC 加密，密钥经 PBKDF2-HMAC-SHA256(10万次迭代) 派生，
/// 每次导出使用随机 salt + IV，防止彩虹表与重放攻击。
class DataMigrationService {
  static const String _magicHeaderV2 = 'LEDGER_BACKUP_V2'; // 新版 AES 加密
  static const String _magicHeaderV1 = 'LEDGER_BACKUP_V1'; // 旧版 XOR（仅为兼容导入保留）

  static const int _pbkdf2Iterations = 100000;
  static const int _keyLength = 32; // AES-256
  static const int _saltLength = 16;
  static const int _ivLength = 16;

  static final Random _secureRandom = Random.secure();

  static Uint8List _randomBytes(int n) {
    final b = Uint8List(n);
    for (var i = 0; i < n; i++) {
      b[i] = _secureRandom.nextInt(256);
    }
    return b;
  }

  /// 导出完整备份（含数据库+凭证图片），返回.ledger文件路径
  static Future<String> exportFullBackup({
    required String password,
    required Database db,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final tempDir = Directory('${appDir.path}/temp_backup_${DateTime.now().millisecondsSinceEpoch}');
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }

    try {
      // 1. 导出数据库为JSON
      final tables = await db.query('sqlite_master', where: 'type = ?', whereArgs: ['table']);
      final dbData = <String, dynamic>{};
      for (final table in tables) {
        final tableName = table['name'] as String;
        if (tableName.startsWith('sqlite_')) continue;
        final rows = await db.query(tableName);
        dbData[tableName] = rows;
      }
      final dbJsonPath = '${tempDir.path}/database.json';
      await File(dbJsonPath).writeAsString(jsonEncode(dbData), flush: true);

      // 2. 复制凭证图片
      final voucherDir = Directory('${appDir.path}/voucher_images');
      if (await voucherDir.exists()) {
        final voucherFiles = await voucherDir.list().toList();
        final voucherBackupDir = Directory('${tempDir.path}/voucher_images');
        if (!await voucherBackupDir.exists()) {
          await voucherBackupDir.create(recursive: true);
        }
        for (final file in voucherFiles) {
          if (file is File) {
            await file.copy('${voucherBackupDir.path}/${p.basename(file.path)}');
          }
        }
      }

      // 3. 写入元数据
      final metadata = {
        'version': '1.0.0',
        'exportTime': DateTime.now().toIso8601String(),
        'appVersion': '1.0.0',
        'encryption': 'AES-256-CBC/PBKDF2',
        'tables': dbData.keys.toList(),
      };
      await File('${tempDir.path}/metadata.json').writeAsString(jsonEncode(metadata), flush: true);

      // 4. 打包为ZIP
      final zipPath = '${tempDir.path}/backup.zip';
      final archive = Archive();
      await _addDirectoryToArchive(archive, tempDir, tempDir.path);
      final zipBytes = ZipEncoder().encode(archive);
      await File(zipPath).writeAsBytes(zipBytes!, flush: true);

      // 5. AES-256-CBC 加密（PBKDF2 派生密钥 + 随机 salt/iv）
      final zipData = await File(zipPath).readAsBytes();
      final salt = _randomBytes(_saltLength);
      final iv = _randomBytes(_ivLength);
      final key = _deriveKeyAes(password, salt);
      final encrypted = _aesCbcEncrypt(key, iv, Uint8List.fromList(zipData));

      // 6. 写入.ledger文件到统一的外部可见备份目录：magic + 分隔符 + salt + iv + 密文
      final backupDir = await PlatformFileService.getBackupDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final ledgerPath = '${backupDir.path}/简帐备份_$timestamp.ledger';

      final output = <int>[];
      output.addAll(utf8.encode(_magicHeaderV2));
      output.add(0);
      output.addAll(salt);
      output.addAll(iv);
      output.addAll(encrypted);
      await File(ledgerPath).writeAsBytes(output, flush: true);

      return ledgerPath;
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  /// 导入.ledger备份文件，恢复全部数据（自动识别 V2 AES 与旧 V1 XOR 格式）
  static Future<Map<String, dynamic>> importFullBackup({
    required String ledgerPath,
    required String password,
    required Database db,
  }) async {
    final file = File(ledgerPath);
    if (!await file.exists()) {
      throw Exception('备份文件不存在');
    }

    final data = await file.readAsBytes();

    // 判断文件版本
    final headerV2 = utf8.encode(_magicHeaderV2);
    final headerV1 = utf8.encode(_magicHeaderV1);
    List<int> zipData;

    if (_matchHeader(data, headerV2)) {
      final body = data.sublist(headerV2.length + 1);
      if (body.length < _saltLength + _ivLength) {
        throw Exception('备份文件已损坏');
      }
      final salt = body.sublist(0, _saltLength);
      final iv = body.sublist(_saltLength, _saltLength + _ivLength);
      final cipherText = body.sublist(_saltLength + _ivLength);
      final key = _deriveKeyAes(password, Uint8List.fromList(salt));
      zipData = _aesCbcDecrypt(key, Uint8List.fromList(iv), Uint8List.fromList(cipherText));
    } else if (_matchHeader(data, headerV1)) {
      // 兼容旧版 XOR 备份
      final encryptedData = data.sublist(headerV1.length + 1);
      final key = _legacyDeriveKey(password);
      final decrypted = _legacyDecrypt(encryptedData, key);
      if (decrypted == null) {
        throw Exception('密码错误或文件已损坏');
      }
      zipData = decrypted;
    } else {
      throw Exception('无效的备份文件格式');
    }

    if (zipData.isEmpty) {
      throw Exception('密码错误或文件已损坏');
    }

    // 解压
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipData);
    } catch (_) {
      throw Exception('密码错误或文件已损坏');
    }

    // 读取元数据
    Map<String, dynamic>? metadata;
    Map<String, dynamic>? dbData;
    for (final file in archive.files) {
      if (file.name == 'metadata.json') {
        metadata = jsonDecode(utf8.decode(file.content as List<int>)) as Map<String, dynamic>;
      } else if (file.name == 'database.json') {
        dbData = jsonDecode(utf8.decode(file.content as List<int>)) as Map<String, dynamic>;
      }
    }

    if (dbData == null) {
      throw Exception('备份文件中没有数据库数据');
    }

    // 恢复数据库
    for (final entry in dbData.entries) {
      final tableName = entry.key;
      final rows = entry.value as List;
      await db.delete(tableName);
      for (final row in rows) {
        try {
          await db.insert(tableName, Map<String, dynamic>.from(row as Map));
        } catch (_) {
          // 跳过单行结构不兼容，保证整体恢复不中断
        }
      }
    }

    // 恢复凭证图片
    final appDir = await getApplicationDocumentsDirectory();
    final voucherDir = Directory('${appDir.path}/voucher_images');
    if (!await voucherDir.exists()) {
      await voucherDir.create(recursive: true);
    }
    for (final file in archive.files) {
      if (file.name.startsWith('voucher_images/') && file.isFile) {
        final fileName = p.basename(file.name);
        final outputPath = '${voucherDir.path}/$fileName';
        await File(outputPath).writeAsBytes(file.content as List<int>);
      }
    }

    return {
      'metadata': metadata,
      'tablesRestored': dbData.keys.length,
      'rowsRestored': dbData.values.fold<int>(0, (sum, list) => sum + (list as List).length),
    };
  }

  /// 验证备份文件密码是否正确
  static Future<bool> verifyPassword(String ledgerPath, String password) async {
    try {
      final file = File(ledgerPath);
      final data = await file.readAsBytes();
      final headerV2 = utf8.encode(_magicHeaderV2);
      final headerV1 = utf8.encode(_magicHeaderV1);
      if (_matchHeader(data, headerV2)) {
        final body = data.sublist(headerV2.length + 1);
        if (body.length < _saltLength + _ivLength) return false;
        final salt = body.sublist(0, _saltLength);
        final iv = body.sublist(_saltLength, _saltLength + _ivLength);
        final cipherText = body.sublist(_saltLength + _ivLength);
        final key = _deriveKeyAes(password, Uint8List.fromList(salt));
        return _aesCbcDecrypt(key, Uint8List.fromList(iv), Uint8List.fromList(cipherText)).isNotEmpty;
      } else if (_matchHeader(data, headerV1)) {
        final encryptedData = data.sublist(headerV1.length + 1);
        return _legacyDecrypt(encryptedData, _legacyDeriveKey(password)) != null;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static bool _matchHeader(List<int> data, List<int> header) {
    if (data.length < header.length + 1) return false;
    for (var i = 0; i < header.length; i++) {
      if (data[i] != header[i]) return false;
    }
    return true;
  }

  // ============ AES-256-CBC + PBKDF2（pointycastle） ============

  static Uint8List _deriveKeyAes(String password, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    derivator.init(Pbkdf2Parameters(salt, _pbkdf2Iterations, _keyLength));
    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }

  static Uint8List _aesCbcEncrypt(Uint8List key, Uint8List iv, Uint8List plain) {
    final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()));
    cipher.init(
      true,
      PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(key), iv), null),
    );
    return cipher.process(plain);
  }

  static Uint8List _aesCbcDecrypt(Uint8List key, Uint8List iv, Uint8List cipherText) {
    try {
      final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()));
      cipher.init(
        false,
        PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(key), iv), null),
      );
      return cipher.process(cipherText);
    } catch (_) {
      // 密码错误会导致 PKCS7 去填充失败
      return Uint8List(0);
    }
  }

  // ============ 旧版 XOR（仅用于导入历史备份，不再用于新建） ============

  static List<int> _legacyDeriveKey(String password) {
    return crypto.sha256.convert(utf8.encode(password)).bytes;
  }

  static List<int>? _legacyDecrypt(List<int> encrypted, List<int> key) {
    if (encrypted.length < 32) return null;
    final storedHash = encrypted.sublist(0, 32);
    final data = <int>[];
    for (var i = 32; i < encrypted.length; i++) {
      data.add(encrypted[i] ^ key[(i - 32) % key.length]);
    }
    final dataHash = crypto.sha256.convert(data).bytes;
    for (var i = 0; i < 32; i++) {
      if (storedHash[i] != dataHash[i]) return null;
    }
    return data;
  }

  // 添加目录到ZIP归档
  static Future<void> _addDirectoryToArchive(Archive archive, Directory dir, String basePath) async {
    final entities = await dir.list().toList();
    for (final entity in entities) {
      if (entity is File) {
        final relativePath = p.relative(entity.path, from: basePath);
        if (relativePath == 'backup.zip') continue;
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
      } else if (entity is Directory) {
        await _addDirectoryToArchive(archive, entity, basePath);
      }
    }
  }
}
