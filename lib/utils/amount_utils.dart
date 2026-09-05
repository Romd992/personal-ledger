import 'package:flutter/material.dart';

/// 金额格式化工具类
/// 支持智能缩写模式和完整显示模式
class AmountUtils {
  /// 千分位格式化 + 两位小数
  /// 例如：15159301570413.0 -> 15,159,301,570,413.00
  static String formatFull(double? value) {
    if (value == null) return '0.00';
    final neg = value < 0;
    final abs = value.abs();
    final fixed = abs.toStringAsFixed(2);
    final parts = fixed.split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '${neg ? '-' : ''}$intPart.${parts.length > 1 ? parts[1] : '00'}';
  }

  /// 智能缩写格式化
  /// <1万：完整显示，如 9,999.00
  /// 1万-1亿：xx.xx万，如 15.16万
  /// 1亿-1万亿：xx.xx亿，如 151.59亿
  /// >1万亿：xx.xx万亿，如 15.16万亿
  static String formatSmart(double? value) {
    if (value == null) return '0.00';
    final neg = value < 0;
    final abs = value.abs();

    if (abs < 10000) {
      return '${neg ? '-' : ''}${formatFull(abs)}';
    } else if (abs < 100000000) {
      // 1万 - 1亿
      final wan = abs / 10000;
      return '${neg ? '-' : ''}${wan.toStringAsFixed(2)}万';
    } else if (abs < 1000000000000) {
      // 1亿 - 1万亿
      final yi = abs / 100000000;
      return '${neg ? '-' : ''}${yi.toStringAsFixed(2)}亿';
    } else {
      // >1万亿
      final wanYi = abs / 1000000000000;
      return '${neg ? '-' : ''}${wanYi.toStringAsFixed(2)}万亿';
    }
  }

  /// 根据显示模式格式化金额
  /// [mode]：'smart' 智能缩写 / 'full' 完整显示
  static String format(double? value, String mode) {
    if (mode == 'full') {
      return formatFull(value);
    }
    return formatSmart(value);
  }

  /// 显示完整金额的弹窗
  static void showFullAmountDialog(BuildContext context, String title, double? value) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: Text(
          '¥${formatFull(value)}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFB8860B)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
