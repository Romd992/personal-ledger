class RecycleItem {
  final int? id;
  final String recordType; // income / expense
  final int recordId;
  final String recordJson; // 记录完整数据JSON
  final String deletedAt;
  final String expireAt; // 30天后过期自动清除

  RecycleItem({
    this.id,
    required this.recordType,
    required this.recordId,
    required this.recordJson,
    required this.deletedAt,
    required this.expireAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'record_type': recordType,
      'record_id': recordId,
      'record_json': recordJson,
      'deleted_at': deletedAt,
      'expire_at': expireAt,
    };
  }

  factory RecycleItem.fromMap(Map<String, dynamic> map) {
    return RecycleItem(
      id: map['id'] as int?,
      recordType: map['record_type'] as String,
      recordId: map['record_id'] as int,
      recordJson: map['record_json'] as String,
      deletedAt: map['deleted_at'] as String,
      expireAt: map['expire_at'] as String,
    );
  }

  // 显示用的名称（客户·商品 / 类型·说明），不含金额，避免一行过长截断金额
  String get displayName {
    try {
      final data = _parseJson(recordJson);
      if (recordType == 'income') {
        final customer = data['customer_name'] ?? '未知客户';
        final product = data['product_name'] ?? '';
        return product.toString().isEmpty ? '$customer' : '$customer · $product';
      } else {
        final typeName = data['expense_type_name'] ?? '支出';
        final note = data['supplier_note'] ?? data['remark'] ?? '';
        return (note == null || note.toString().isEmpty) ? '$typeName' : '$typeName · $note';
      }
    } catch (_) {
      return '已删除记录 #$recordId';
    }
  }

  // 显示用的金额（固定2位小数）
  String get displayAmount {
    try {
      final data = _parseJson(recordJson);
      final amt = double.tryParse('${data['amount'] ?? 0}') ?? 0;
      return '¥${amt.toStringAsFixed(2)}';
    } catch (_) {
      return '¥0.00';
    }
  }

  // 兼容旧调用：标题即名称
  String get displayTitle => displayName;

  Map<String, dynamic> _parseJson(String jsonStr) {
    // 简单解析，避免引入额外依赖
    final result = <String, dynamic>{};
    try {
      jsonStr = jsonStr.trim();
      if (jsonStr.startsWith('{') && jsonStr.endsWith('}')) {
        jsonStr = jsonStr.substring(1, jsonStr.length - 1);
        final pairs = <String>[];
        var depth = 0;
        var current = StringBuffer();
        for (var i = 0; i < jsonStr.length; i++) {
          final char = jsonStr[i];
          if (char == '{' || char == '[') depth++;
          if (char == '}' || char == ']') depth--;
          if (char == ',' && depth == 0) {
            pairs.add(current.toString());
            current = StringBuffer();
          } else {
            current.write(char);
          }
        }
        if (current.isNotEmpty) pairs.add(current.toString());
        for (var pair in pairs) {
          final idx = pair.indexOf(':');
          if (idx > 0) {
            final key = pair.substring(0, idx).trim().replaceAll('"', '');
            final value = pair.substring(idx + 1).trim().replaceAll('"', '');
            result[key] = value;
          }
        }
      }
    } catch (_) {}
    return result;
  }
}
