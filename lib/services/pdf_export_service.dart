import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

/// 客户对账单PDF导出服务
class PdfExportService {
  /// 生成客户对账单PDF
  static Future<String> exportCustomerStatement({
    required String customerName,
    required DateTime startDate,
    required DateTime endDate,
    required List<Map<String, dynamic>> transactions,
  }) async {
    final pdf = pw.Document();

    final dateFormat = DateFormat('yyyy年MM月dd日');
    final moneyFormat = NumberFormat('#,##0.00');

    // 计算汇总
    double totalAmount = 0;
    double paidAmount = 0;
    double unpaidAmount = 0;
    int invoicedCount = 0;
    int uninvoicedCount = 0;

    for (final t in transactions) {
      final amount = (t['amount'] as num?)?.toDouble() ?? 0;
      totalAmount += amount;
      // 兼容 paymentStatus('paid'/'unpaid') 与旧 isPaid(bool)
      final dynamic rawPaid = t['paymentStatus'] ?? t['isPaid'];
      final isPaid = rawPaid == null ? true : (rawPaid is bool ? rawPaid : rawPaid != 'unpaid');
      if (isPaid) {
        paidAmount += amount;
      } else {
        unpaidAmount += amount;
      }
      // 兼容 invoiceType('none'/'general'/'special') 与旧 invoiceStatus 中文
      final dynamic rawInv = t['invoiceType'] ?? t['invoiceStatus'];
      final bool invoiced = rawInv == 'general' || rawInv == 'special' || rawInv == '已开票';
      final bool uninvoiced = rawInv == 'none' || rawInv == '未开票';
      if (invoiced) {
        invoicedCount++;
      } else if (uninvoiced) {
        uninvoicedCount++;
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // 标题
          pw.Center(
            child: pw.Text(
              '客户对账单',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(
              '客户：$customerName',
              style: pw.TextStyle(fontSize: 16),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              '对账周期：${dateFormat.format(startDate)} 至 ${dateFormat.format(endDate)}',
              style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              '生成时间：${dateFormat.format(DateTime.now())}',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey500),
            ),
          ),
          pw.SizedBox(height: 20),

          // 汇总信息
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem('交易笔数', '${transactions.length}笔'),
                _buildSummaryItem('总金额', '¥${moneyFormat.format(totalAmount)}'),
                _buildSummaryItem('已收款', '¥${moneyFormat.format(paidAmount)}'),
                _buildSummaryItem('未收款', '¥${moneyFormat.format(unpaidAmount)}'),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // 交易明细表头
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: const pw.BoxDecoration(color: PdfColors.amber100),
            child: pw.Row(
              children: [
                pw.Expanded(flex: 2, child: pw.Text('日期', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                pw.Expanded(flex: 3, child: pw.Text('商品/备注', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                pw.Expanded(flex: 2, child: pw.Text('金额', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.right)),
                pw.Expanded(flex: 1, child: pw.Text('付款', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.center)),
                pw.Expanded(flex: 1, child: pw.Text('开票', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.center)),
              ],
            ),
          ),

          // 交易明细
          ...transactions.asMap().entries.map((entry) {
            final index = entry.key;
            final t = entry.value;
            // 兼容日期为 String 或 DateTime 两种入参，避免 String as DateTime? 强转崩溃
            final dynamic rawDate = t['date'];
            final date = rawDate is DateTime
                ? rawDate
                : DateTime.tryParse('$rawDate') ?? DateTime.now();
            // 兼容 productName / goods / note 多种字段名
            final goods = (t['productName'] ?? t['goods'] ?? t['note'] ?? '') as String;
            final amount = (t['amount'] as num?)?.toDouble() ?? 0;
            // 兼容 paymentStatus('paid'/'unpaid') 与旧 isPaid(bool) 两种字段
            final dynamic rawPaid = t['paymentStatus'] ?? t['isPaid'];
            final isPaid = rawPaid == null ? true : (rawPaid is bool ? rawPaid : rawPaid != 'unpaid');
            // 兼容 invoiceType('none'/'general'/'special') 与旧 invoiceStatus 中文
            final dynamic rawInv = t['invoiceType'] ?? t['invoiceStatus'];
            final invoiceStatus = rawInv == 'special'
                ? '专票'
                : rawInv == 'general'
                    ? '普票'
                    : (rawInv is String && rawInv.isNotEmpty ? rawInv as String : '不需要');

            return pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              decoration: pw.BoxDecoration(
                color: index % 2 == 0 ? PdfColors.white : PdfColors.grey50,
                border: const pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5)),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(flex: 2, child: pw.Text(dateFormat.format(date), style: pw.TextStyle(fontSize: 9))),
                  pw.Expanded(flex: 3, child: pw.Text(goods, style: pw.TextStyle(fontSize: 9), maxLines: 2)),
                  pw.Expanded(flex: 2, child: pw.Text('¥${moneyFormat.format(amount)}', style: pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.right)),
                  pw.Expanded(flex: 1, child: pw.Text(isPaid ? '已付' : '未付', style: pw.TextStyle(fontSize: 9, color: isPaid ? PdfColors.green : PdfColors.red), textAlign: pw.TextAlign.center)),
                  pw.Expanded(flex: 1, child: pw.Text(invoiceStatus, style: pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center)),
                ],
              ),
            );
          }).toList(),

          pw.SizedBox(height: 20),

          // 底部合计
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.amber50,
              border: pw.Border.all(color: PdfColors.amber200, width: 1),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('合计：', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.Text('¥${moneyFormat.format(totalAmount)}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('已收款：', style: pw.TextStyle(fontSize: 12, color: PdfColors.green)),
                    pw.Text('¥${moneyFormat.format(paidAmount)}', style: pw.TextStyle(fontSize: 12, color: PdfColors.green)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('未收款：', style: pw.TextStyle(fontSize: 12, color: PdfColors.red)),
                    pw.Text('¥${moneyFormat.format(unpaidAmount)}', style: pw.TextStyle(fontSize: 12, color: PdfColors.red)),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  '已开票：$invoicedCount笔，未开票：$uninvoicedCount笔',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 30),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('客户签字：_______________', style: pw.TextStyle(fontSize: 12)),
              pw.Text('日期：_______________', style: pw.TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    );

    // 保存PDF
    final appDir = await getApplicationDocumentsDirectory();
    final outputDir = Directory('${appDir.path}/pdf_exports');
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final outputPath = '${outputDir.path}/对账单_${customerName}_$timestamp.pdf';
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(await pdf.save());

    return outputPath;
  }

  static pw.Widget _buildSummaryItem(String label, String value) {
    return pw.Column(
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        pw.SizedBox(height: 4),
        pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }
}
