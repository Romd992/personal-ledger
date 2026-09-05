import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:excel/excel.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/platform_file_service.dart';
import '../providers/data_providers.dart';
import 'wifi_transfer_page.dart';
import 'import_backup_page.dart';

class BackupExportPage extends ConsumerStatefulWidget {
  const BackupExportPage({super.key});

  @override
  ConsumerState<BackupExportPage> createState() => _BackupExportPageState();
}

class _BackupExportPageState extends ConsumerState<BackupExportPage> {
  bool _exporting = false;
  bool _importing = false;

  // 导出数据备份（JSON格式）
  Future<void> _exportBackup() async {
    setState(() => _exporting = true);
    try {
      final data = await DatabaseService.instance.exportAllData();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final fileName = '记账备份_${DateTime.now().toString().substring(0, 10).replaceAll('-', '')}_${DateTime.now().millisecondsSinceEpoch}.json';

      // 使用平台适配服务保存文件
      final savedPath = await PlatformFileService.saveFile(
        fileName: fileName,
        bytes: utf8.encode(jsonStr),
        dialogTitle: '导出数据备份',
      );

      if (mounted) {
        if (savedPath != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('备份已保存到：$savedPath')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('备份文件已生成，请选择保存位置')),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败: $e'), backgroundColor: AppTheme.expenseRed));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // 导入数据备份（跳转到自动搜索页面）
  Future<void> _importBackup() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ImportBackupPage()),
    );
    if (result == true && mounted) {
      Navigator.pop(context);
    }
  }

  // 导出Excel
  Future<void> _exportExcel(String type) async {
    setState(() => _exporting = true);
    try {
      final excel = Excel.createExcel();
      excel.delete('Sheet1');

      // 统一表格美化：金色表头(#B8860B)白字加粗居中、正文垂直居中自动换行、金额右对齐
      final headerStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('FFB8860B'),
        fontColorHex: ExcelColor.white,
        bold: true,
        fontSize: 11,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
      );
      final bodyStyle = CellStyle(verticalAlign: VerticalAlign.Center, horizontalAlign: HorizontalAlign.Left, textWrapping: TextWrapping.WrapText);
      final numStyle = CellStyle(verticalAlign: VerticalAlign.Center, horizontalAlign: HorizontalAlign.Right);
      final centerStyle = CellStyle(verticalAlign: VerticalAlign.Center, horizontalAlign: HorizontalAlign.Center);

      // 写入一行并按列设置样式（header=表头；rightCols 金额列右对齐；centerCols 状态列居中）
      void styledRow(Sheet s, List<dynamic> values, {bool header = false, Set<int> rightCols = const {}, Set<int> centerCols = const {}}) {
        final r = s.rows.length;
        for (var c = 0; c < values.length; c++) {
          final cell = s.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
          cell.value = TextCellValue(values[c].toString());
          cell.cellStyle = header
              ? headerStyle
              : rightCols.contains(c)
                  ? numStyle
                  : centerCols.contains(c)
                      ? centerStyle
                      : bodyStyle;
        }
      }

      // 统一列宽 + 表头行高
      void applyWidths(Sheet s, List<double> widths) {
        for (var i = 0; i < widths.length; i++) {
          s.setColumnWidth(i, widths[i]);
        }
        s.setRowHeight(0, 26);
      }

      String invoiceText(String t) => t == 'none' ? '不开票' : t == 'general' ? '普票' : '专票';

      if (type == 'income' || type == 'all') {
        final sheet = excel['收入明细'];
        styledRow(sheet, ['日期', '客户名称', '采购内容', '数量', '单价', '金额(价税合计)', '成本', '发票类型', '税率', '税额', '不含税收入', '毛利', '收款状态', '收款日期', '备注'], header: true);
        final incomes = await DatabaseService.instance.getIncomes();
        for (var inc in incomes) {
          styledRow(sheet, [
            inc.date, inc.customerName, inc.productName ?? '',
            inc.quantity ?? '', inc.unitPrice ?? '', inc.amount.toStringAsFixed(2), inc.cost.toStringAsFixed(2),
            invoiceText(inc.invoiceType),
            '${(inc.taxRate * 100).toInt()}%', inc.taxAmount.toStringAsFixed(2), inc.amountExcludingTax.toStringAsFixed(2), inc.grossProfit.toStringAsFixed(2),
            inc.paymentStatus == 'paid' ? '已收款' : '未收款', inc.paymentDate ?? '', inc.remark ?? '',
          ], rightCols: {3, 4, 5, 6, 8, 9, 10, 11}, centerCols: {7, 12});
        }
        applyWidths(sheet, [12, 14, 20, 8, 10, 16, 10, 10, 8, 11, 14, 12, 10, 12, 26]);
      }

      if (type == 'expense' || type == 'all') {
        final sheet = excel['支出明细'];
        styledRow(sheet, ['日期', '支出类型', '供应商/说明', '金额', '发票类型', '税率', '进项税额', '付款状态', '付款日期', '备注'], header: true);
        final expenses = await DatabaseService.instance.getExpenses();
        for (var exp in expenses) {
          styledRow(sheet, [
            exp.date, exp.expenseTypeName ?? '', exp.supplierNote ?? '', exp.amount.toStringAsFixed(2),
            invoiceText(exp.invoiceType),
            '${(exp.taxRate * 100).toInt()}%', exp.taxAmount.toStringAsFixed(2),
            exp.paymentStatus == 'paid' ? '已付款' : '未付款', exp.paymentDate ?? '', exp.remark ?? '',
          ], rightCols: {3, 5, 6}, centerCols: {4, 7});
        }
        applyWidths(sheet, [12, 12, 22, 12, 10, 8, 12, 10, 12, 26]);
      }

      if (type == 'all') {
        final sheet = excel['统计汇总'];
        styledRow(sheet, ['项目', '金额'], header: true);
        final incomeStats = await DatabaseService.instance.getIncomeStats();
        final expenseStats = await DatabaseService.instance.getExpenseStats();
        // 净利润口径与首页/统计一致：一般纳税人专票进项税可抵扣、不重复计入费用
        final prefs = await SharedPreferences.getInstance();
        final isSmallTaxpayer = prefs.getString('taxpayer_type') == 'small';
        final deductibleExpenseTax = isSmallTaxpayer ? 0.0 : (expenseStats['deductibleTax'] ?? 0);
        final summaryRows = <List<dynamic>>[
          ['收入总额(价税合计)', (incomeStats['totalAmount'] ?? 0).toStringAsFixed(2)],
          ['收入总额(不含税)', (incomeStats['totalExcludingTax'] ?? 0).toStringAsFixed(2)],
          ['总成本', (incomeStats['totalCost'] ?? 0).toStringAsFixed(2)],
          ['销项税额', (incomeStats['totalTax'] ?? 0).toStringAsFixed(2)],
          ['毛利润', (incomeStats['totalGrossProfit'] ?? 0).toStringAsFixed(2)],
          ['已收款', (incomeStats['paidAmount'] ?? 0).toStringAsFixed(2)],
          ['未收款', (incomeStats['unpaidAmount'] ?? 0).toStringAsFixed(2)],
          ['支出总额', (expenseStats['totalAmount'] ?? 0).toStringAsFixed(2)],
          ['进项税额', (expenseStats['totalTax'] ?? 0).toStringAsFixed(2)],
          ['已付款', (expenseStats['paidAmount'] ?? 0).toStringAsFixed(2)],
          ['未付款', (expenseStats['unpaidAmount'] ?? 0).toStringAsFixed(2)],
          ['净利润', ((incomeStats['totalGrossProfit'] ?? 0) - ((expenseStats['totalAmount'] ?? 0) - deductibleExpenseTax)).toStringAsFixed(2)],
          ['应交增值税', ((incomeStats['totalTax'] ?? 0) - (expenseStats['totalTax'] ?? 0)).toStringAsFixed(2)],
        ];
        for (final row in summaryRows) {
          styledRow(sheet, row, rightCols: {1});
        }
        applyWidths(sheet, [26, 18]);
      }

      final typeName = type == 'income' ? '收入明细' : type == 'expense' ? '支出明细' : '全部数据';
      final fileName = '记账_${typeName}_${DateTime.now().toString().substring(0, 10).replaceAll('-', '')}.xlsx';
      final bytes = excel.encode();

      // 使用平台适配服务保存文件
      final savedPath = await PlatformFileService.saveFile(
        fileName: fileName,
        bytes: bytes!,
        dialogTitle: '导出$typeName Excel',
      );

      if (mounted) {
        if (savedPath != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Excel已保存到：$savedPath')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Excel文件已生成，请选择保存位置')),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败: $e'), backgroundColor: AppTheme.expenseRed));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // 导出CSV（带UTF-8 BOM，Excel/WPS可直接打开中文）
  Future<void> _exportCSV(String type) async {
    setState(() => _exporting = true);
    try {
      final dir = await getTemporaryDirectory();
      final generatedFiles = <Map<String, dynamic>>[];
      String csvEscape(String v) {
        if (v.contains(',') || v.contains('"') || v.contains('\n')) {
          return '"${v.replaceAll('"', '""')}"';
        }
        return v;
      }
      final dateTag = DateTime.now().toString().substring(0, 10).replaceAll('-', '');

      if (type == 'income' || type == 'all') {
        final buf = StringBuffer();
        buf.write('\uFEFF');
        buf.writeln(['日期','客户名称','采购内容','数量','单价','金额(价税合计)','成本','发票类型','税率','税额','不含税收入','毛利','收款状态','收款日期','备注'].map(csvEscape).join(','));
        final incomes = await DatabaseService.instance.getIncomes();
        for (var inc in incomes) {
          buf.writeln([
            inc.date, inc.customerName, inc.productName ?? '',
            inc.quantity?.toString() ?? '', inc.unitPrice?.toStringAsFixed(2) ?? '',
            inc.amount.toStringAsFixed(2), inc.cost.toStringAsFixed(2),
            inc.invoiceType == 'none' ? '不开票' : inc.invoiceType == 'general' ? '普票' : '专票',
            '${(inc.taxRate * 100).toInt()}%', inc.taxAmount.toStringAsFixed(2),
            inc.amountExcludingTax.toStringAsFixed(2), inc.grossProfit.toStringAsFixed(2),
            inc.paymentStatus == 'paid' ? '已收' : '未收', inc.paymentDate ?? '', inc.remark ?? '',
          ].map(csvEscape).join(','));
        }
        final f = File('${dir.path}/收入明细_$dateTag.csv');
        await f.writeAsString(buf.toString());
        generatedFiles.add({'name': '收入明细_$dateTag.csv', 'path': f.path, 'bytes': await f.readAsBytes()});
      }

      if (type == 'expense' || type == 'all') {
        final buf = StringBuffer();
        buf.write('\uFEFF');
        buf.writeln(['日期','支出类型','供应商/说明','金额','发票类型','税率','进项税额','付款状态','付款日期','备注'].map(csvEscape).join(','));
        final expenses = await DatabaseService.instance.getExpenses();
        for (var exp in expenses) {
          buf.writeln([
            exp.date, exp.expenseTypeName ?? '', exp.supplierNote ?? '', exp.amount.toStringAsFixed(2),
            exp.invoiceType == 'none' ? '不开票' : exp.invoiceType == 'general' ? '普票' : '专票',
            '${(exp.taxRate * 100).toInt()}%', exp.taxAmount.toStringAsFixed(2),
            exp.paymentStatus == 'paid' ? '已付' : '未付', exp.paymentDate ?? '', exp.remark ?? '',
          ].map(csvEscape).join(','));
        }
        final f = File('${dir.path}/支出明细_$dateTag.csv');
        await f.writeAsString(buf.toString());
        generatedFiles.add({'name': '支出明细_$dateTag.csv', 'path': f.path, 'bytes': await f.readAsBytes()});
      }

      final typeName = type == 'income' ? '收入明细' : type == 'expense' ? '支出明细' : '全部数据';

      if (PlatformFileService.isWindows) {
        // Windows: 分别保存每个文件
        final savedPaths = <String>[];
        for (final f in generatedFiles) {
          final saved = await PlatformFileService.saveFile(
            fileName: f['name'] as String,
            bytes: f['bytes'] as List<int>,
            dialogTitle: '导出${f['name']}',
          );
          if (saved != null) savedPaths.add(saved);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已保存${savedPaths.length}个CSV文件')),
          );
        }
      } else {
        // Android: 用系统分享
        final xFiles = generatedFiles.map((f) => XFile(f['path'] as String, name: f['name'] as String)).toList();
        await Share.shareXFiles(xFiles, text: '简帐$typeName CSV导出');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('CSV文件已生成，请选择保存位置')),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败: $e'), backgroundColor: AppTheme.expenseRed));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('备份与导出')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionTitle('数据备份'),
          const SizedBox(height: 8),
          _buildActionCard(
            icon: Icons.backup,
            title: '导出数据备份',
            subtitle: '导出所有数据为JSON文件，可用于恢复或迁移',
            color: AppTheme.primaryGold,
            onTap: _exporting ? null : _exportBackup,
            loading: _exporting,
          ),
          const SizedBox(height: 12),
          _buildActionCard(
            icon: Icons.restore,
            title: '导入数据备份',
            subtitle: '从JSON备份文件恢复数据（将覆盖当前数据）',
            color: AppTheme.infoBlue,
            onTap: _importing ? null : _importBackup,
            loading: _importing,
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('WiFi直传'),
          const SizedBox(height: 8),
          _buildActionCard(
            icon: Icons.wifi,
            title: '同WiFi设备互传',
            subtitle: '两台设备连同一WiFi，无需流量快速传输数据',
            color: Colors.teal,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WifiTransferPage())),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('Excel导出'),
          const SizedBox(height: 8),
          _buildActionCard(
            icon: Icons.receipt_long,
            title: '导出收入明细',
            subtitle: '导出所有收入记录为Excel表格',
            color: AppTheme.incomeGreen,
            onTap: _exporting ? null : () => _exportExcel('income'),
          ),
          const SizedBox(height: 12),
          _buildActionCard(
            icon: Icons.shopping_cart,
            title: '导出支出明细',
            subtitle: '导出所有支出记录为Excel表格',
            color: AppTheme.expenseRed,
            onTap: _exporting ? null : () => _exportExcel('expense'),
          ),
          const SizedBox(height: 12),
          _buildActionCard(
            icon: Icons.assessment,
            title: '导出全部数据（含汇总）',
            subtitle: '收入+支出+统计汇总，三个Sheet',
            color: AppTheme.warningOrange,
            onTap: _exporting ? null : () => _exportExcel('all'),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('CSV导出（带中文编码，Excel/WPS直接打开）'),
          const SizedBox(height: 8),
          _buildActionCard(
            icon: Icons.table_chart_outlined,
            title: '导出收入明细 CSV',
            subtitle: '纯文本表格格式，体积小、兼容性强',
            color: AppTheme.incomeGreen,
            onTap: _exporting ? null : () => _exportCSV('income'),
          ),
          const SizedBox(height: 12),
          _buildActionCard(
            icon: Icons.remove_shopping_cart_outlined,
            title: '导出支出明细 CSV',
            subtitle: '纯文本表格格式，体积小、兼容性强',
            color: AppTheme.expenseRed,
            onTap: _exporting ? null : () => _exportCSV('expense'),
          ),
          const SizedBox(height: 12),
          _buildActionCard(
            icon: Icons.folder_zip_outlined,
            title: '导出全部 CSV（收入+支出）',
            subtitle: '同时生成收入和支出两个CSV文件',
            color: AppTheme.warningOrange,
            onTap: _exporting ? null : () => _exportCSV('all'),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('说明'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                Text('• 备份文件包含所有收入、支出、客户、支出类型数据', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                SizedBox(height: 6),
                Text('• 导入备份将覆盖当前所有数据，请谨慎操作', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                SizedBox(height: 6),
                Text('• Excel导出可在手机或电脑上用WPS/Excel打开', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                SizedBox(height: 6),
                Text('• 所有数据仅存储在本地，不会上传到任何服务器', style: TextStyle(fontSize: 13, color: AppTheme.incomeGreen)),
              ]),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(children: [Container(width: 4, height: 18, decoration: BoxDecoration(color: AppTheme.primaryGold, borderRadius: BorderRadius.circular(2))), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))]);
  }

  Widget _buildActionCard({required IconData icon, required String title, required String subtitle, required Color color, required VoidCallback? onTap, bool loading = false}) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 24)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)), const SizedBox(height: 2), Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textHint))])),
            if (loading) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) else const Icon(Icons.chevron_right, color: AppTheme.textHint),
          ]),
        ),
      ),
    );
  }
}
