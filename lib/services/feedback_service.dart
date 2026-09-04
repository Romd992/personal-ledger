import 'dart:convert';
import 'package:http/http.dart' as http;
import 'update_service.dart';

/// 企业微信机器人反馈服务
/// 用户在App内直接输入反馈内容，提交到企业微信群
class FeedbackService {
  // 企业微信机器人Webhook URL（用户配置）
  static const String _webhookUrl =
      'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=88942186-99dc-43e7-8497-ef875739445a';

  /// 提交反馈到企业微信群
  /// 
  /// [content] 反馈内容
  /// [contact] 联系方式（可选）
  /// 
  /// 返回 true 表示提交成功，false 表示失败
  static Future<bool> submitFeedback(String content, {String? contact}) async {
    try {
      // 构造markdown格式的消息
      final now = DateTime.now();
      final timeStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';

      final markdownContent = StringBuffer();
      markdownContent.writeln('## 📝 个人记账App反馈');
      markdownContent.writeln('');
      markdownContent.writeln('**反馈内容：**');
      markdownContent.writeln('> $content');
      markdownContent.writeln('');
      if (contact != null && contact.trim().isNotEmpty) {
        markdownContent.writeln('**联系方式：** $contact');
        markdownContent.writeln('');
      }
      markdownContent.writeln('**App版本：** v${UpdateService.currentVersionName} (${UpdateService.currentVersionCode})');
      markdownContent.writeln('**反馈时间：** $timeStr');

      final body = jsonEncode({
        'msgtype': 'markdown',
        'markdown': {
          'content': markdownContent.toString(),
        },
      });

      final response = await http.post(
        Uri.parse(_webhookUrl),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: body,
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final errcode = result['errcode'] ?? -1;
        return errcode == 0;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}
