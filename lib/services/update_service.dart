import 'dart:convert';
import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';

/// 版本信息
class AppVersion {
  final String versionName; // 如 "2.1.4"
  final int versionCode;    // 如 10
  final String downloadUrl;
  final String releaseNotes;
  final DateTime? releaseDate;

  AppVersion({
    required this.versionName,
    required this.versionCode,
    required this.downloadUrl,
    required this.releaseNotes,
    this.releaseDate,
  });

  factory AppVersion.fromJson(Map<String, dynamic> json) {
    return AppVersion(
      versionName: json['versionName'] ?? json['latestVersion'] ?? '0.0.0',
      versionCode: (json['versionCode'] ?? 0) as int,
      downloadUrl: json['downloadUrl'] ?? '',
      releaseNotes: json['releaseNotes'] ?? json['changelog'] ?? '',
      releaseDate: json['releaseDate'] != null
          ? DateTime.tryParse(json['releaseDate'] as String)
          : null,
    );
  }
}

/// 版本检测结果
class UpdateCheckResult {
  final bool hasUpdate;
  final AppVersion? latestVersion;
  final String? error;

  UpdateCheckResult({
    required this.hasUpdate,
    this.latestVersion,
    this.error,
  });

  factory UpdateCheckResult.error(String msg) =>
      UpdateCheckResult(hasUpdate: false, error: msg);
}

/// 版本检测服务
class UpdateService {
  // 版本信息JSON地址（surge.sh静态托管）
  static const String _versionUrl =
      'https://personal-ledger-v2.surge.sh/version.json';

  // 当前应用版本（启动时由 initVersion() 从系统读取，不再硬编码）
  static String currentVersionName = '1.0.0';
  static int currentVersionCode = 1;

  /// 启动时调用：从系统读取真实版本号，避免硬编码与实际安装版本不一致
  static Future<void> initVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      currentVersionName = info.version;
      currentVersionCode = int.tryParse(info.buildNumber) ?? 1;
    } catch (_) {
      // 读取失败保留默认值
    }
  }

  /// 检测更新
  static Future<UpdateCheckResult> checkUpdate() async {
    try {
      final uri = Uri.parse(_versionUrl);
      final httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(seconds: 10);

      final request = await httpClient.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) {
        httpClient.close();
        return UpdateCheckResult.error('服务器响应异常（${response.statusCode}）');
      }

      final body = await response.transform(utf8.decoder).join();
      httpClient.close();

      final json = jsonDecode(body) as Map<String, dynamic>;
      final latest = AppVersion.fromJson(json);

      final hasUpdate = latest.versionCode > currentVersionCode;

      return UpdateCheckResult(
        hasUpdate: hasUpdate,
        latestVersion: latest,
      );
    } on SocketException {
      return UpdateCheckResult.error('网络连接失败，请检查网络后重试');
    } on HttpException {
      return UpdateCheckResult.error('网络请求异常');
    } on FormatException {
      return UpdateCheckResult.error('版本信息格式错误');
    } catch (e) {
      return UpdateCheckResult.error('检测失败：$e');
    }
  }

  /// 比较版本号（辅助方法，用于显示）
  static bool isNewer(String remoteVersion, String localVersion) {
    final remoteParts = remoteVersion.split('.').map(int.tryParse).toList();
    final localParts = localVersion.split('.').map(int.tryParse).toList();
    for (var i = 0; i < 3; i++) {
      final r = i < remoteParts.length ? remoteParts[i] ?? 0 : 0;
      final l = i < localParts.length ? localParts[i] ?? 0 : 0;
      if (r > l) return true;
      if (r < l) return false;
    }
    return false;
  }
}
