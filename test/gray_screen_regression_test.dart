// 首页变灰根因回归测试：
// SQLite 的 SUM 在“某列整月为 0（只记收入未记支出等单边数据）”时返回 int，
// 旧代码直接 as double 会在 build 阶段抛 int!=double，release 版渲染成整屏灰色。
// 本测试复现该数据形态，验证修复后的清洗逻辑对 int/double 都安全。
import 'package:flutter_test/flutter_test.dart';

/// 复刻修复后 database_service.getMonthlyTrend 的清洗逻辑
List<Map<String, dynamic>> cleanTrend(List<Map<String, Object?>> raw) {
  return raw.reversed.map((row) => <String, dynamic>{
    'month': '${row['month']}',
    'income': (row['income'] as num).toDouble(),
    'expense': (row['expense'] as num).toDouble(),
  }).toList();
}

/// 复刻修复后首页 _maxY 逻辑
double calcMaxY(List<Map<String, dynamic>> trend) {
  double max = 0;
  for (var m in trend) {
    final income = (m['income'] as num).toDouble();
    final expense = (m['expense'] as num).toDouble();
    max = [max, income, expense].reduce((a, b) => a > b ? a : b);
  }
  return max <= 0 ? 1 : max * 1.2;
}

void main() {
  test('旧写法对 int 强转 double 确实会抛异常（证明根因真实存在）', () {
    const int zero = 0;
    expect(() => zero as double, throwsA(isA<TypeError>()));
  });

  test('单边数据：本月只有收入(整数)、支出为整数0，清洗后全部为 double 不崩', () {
    // 这正是用户“记一笔收入后变灰”的数据形态：expense 列为 int 0
    final raw = [
      {'month': '2026-09', 'income': 7161, 'expense': 0}, // 两个都是 int
    ];
    final cleaned = cleanTrend(raw);
    expect(cleaned.first['income'], isA<double>());
    expect(cleaned.first['expense'], isA<double>());
    expect(cleaned.first['income'], 7161.0);
    expect(cleaned.first['expense'], 0.0);
    expect(cleaned.first['month'], isA<String>());
  });

  test('混合 int/double 数据都能安全清洗', () {
    final raw = [
      {'month': '2026-07', 'income': 100.5, 'expense': 0},      // double + int
      {'month': '2026-08', 'income': 0, 'expense': 88},          // int + int
      {'month': '2026-09', 'income': 7161.0, 'expense': 23.0},   // double + double
    ];
    final cleaned = cleanTrend(raw);
    for (final row in cleaned) {
      expect(row['income'], isA<double>());
      expect(row['expense'], isA<double>());
    }
    // reversed 后顺序应为 09,08,07
    expect(cleaned.first['month'], '2026-09');
  });

  test('_maxY 全 0 时返回非 0 上限，普通数据返回 1.2 倍最大值', () {
    expect(calcMaxY([
      {'income': 0.0, 'expense': 0.0},
    ]), 1);
    expect(calcMaxY([
      {'income': 100.0, 'expense': 50.0},
    ]), 120.0);
  });

  test('清洗后的数据走首页/统计页的 as num.toDouble 渲染路径不再抛异常', () {
    final cleaned = cleanTrend([
      {'month': '2026-09', 'income': 7161, 'expense': 0},
    ]);
    // 模拟 build 中柱状图取值
    for (final m in cleaned) {
      expect(() {
        final income = (m['income'] as num).toDouble();
        final expense = (m['expense'] as num).toDouble();
        final v = income - expense;
        return v.toStringAsFixed(2);
      }, returnsNormally);
    }
  });
}
