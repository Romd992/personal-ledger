class Income {
  final int? id;
  final String date; // YYYY-MM-DD
  final String customerName;
  final String productName; // 采购内容
  final double? quantity;
  final double? unitPrice;
  final double amount; // 价税合计
  final double cost; // 成本
  final String invoiceType; // none(不开票)/general(普票)/special(专票)
  final double taxRate; // 税率，如0.13
  final double taxAmount; // 税额
  final double amountExcludingTax; // 不含税收入
  final double grossProfit; // 毛利 = 不含税收入 - 成本
  final String paymentStatus; // paid(已收)/unpaid(未收)
  final String? paymentDate; // 收款日期
  final String? remark;
  final int bookId; // 所属账本ID
  final List<String>? voucherImages; // 凭证图片路径列表
  final String createdAt;
  final String updatedAt;

  Income({
    this.id,
    required this.date,
    required this.customerName,
    required this.productName,
    this.quantity,
    this.unitPrice,
    required this.amount,
    this.cost = 0,
    this.invoiceType = 'none',
    this.taxRate = 0,
    this.taxAmount = 0,
    this.amountExcludingTax = 0,
    this.grossProfit = 0,
    this.paymentStatus = 'paid',
    this.paymentDate,
    this.remark,
    this.bookId = 1,
    this.voucherImages,
    required this.createdAt,
    required this.updatedAt,
  });

  // 计算税务和利润
  static Map<String, double> calculate({
    required double amount,
    double cost = 0,
    String invoiceType = 'none',
    double taxRate = 0,
  }) {
    double taxAmount = 0;
    double amountExcludingTax = amount;

    if (invoiceType != 'none' && taxRate > 0) {
      // 价税合计 = 不含税收入 × (1 + 税率)
      // 不含税收入 = 价税合计 / (1 + 税率)
      amountExcludingTax = amount / (1 + taxRate);
      taxAmount = amount - amountExcludingTax;
    }

    double grossProfit = amountExcludingTax - cost;

    return {
      'taxAmount': double.parse(taxAmount.toStringAsFixed(2)),
      'amountExcludingTax': double.parse(amountExcludingTax.toStringAsFixed(2)),
      'grossProfit': double.parse(grossProfit.toStringAsFixed(2)),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'customer_name': customerName,
      'product_name': productName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'amount': amount,
      'cost': cost,
      'invoice_type': invoiceType,
      'tax_rate': taxRate,
      'tax_amount': taxAmount,
      'amount_excluding_tax': amountExcludingTax,
      'gross_profit': grossProfit,
      'payment_status': paymentStatus,
      'payment_date': paymentDate,
      'remark': remark,
      'book_id': bookId,
      'voucher_images': voucherImages != null ? voucherImages!.join('|') : null,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory Income.fromMap(Map<String, dynamic> map) {
    return Income(
      id: map['id'] as int?,
      date: map['date'] as String,
      customerName: map['customer_name'] as String,
      productName: map['product_name'] as String,
      quantity: (map['quantity'] as num?)?.toDouble(),
      unitPrice: (map['unit_price'] as num?)?.toDouble(),
      amount: (map['amount'] as num).toDouble(),
      cost: (map['cost'] as num?)?.toDouble() ?? 0,
      invoiceType: map['invoice_type'] as String? ?? 'none',
      taxRate: (map['tax_rate'] as num?)?.toDouble() ?? 0,
      taxAmount: (map['tax_amount'] as num?)?.toDouble() ?? 0,
      amountExcludingTax: (map['amount_excluding_tax'] as num?)?.toDouble() ?? 0,
      grossProfit: (map['gross_profit'] as num?)?.toDouble() ?? 0,
      paymentStatus: map['payment_status'] as String? ?? 'paid',
      paymentDate: map['payment_date'] as String?,
      remark: map['remark'] as String?,
      bookId: (map['book_id'] as num?)?.toInt() ?? 1,
      voucherImages: map['voucher_images'] != null && (map['voucher_images'] as String).isNotEmpty
          ? (map['voucher_images'] as String).split('|')
          : null,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  Income copyWith({
    int? id,
    String? date,
    String? customerName,
    String? productName,
    double? quantity,
    double? unitPrice,
    double? amount,
    double? cost,
    String? invoiceType,
    double? taxRate,
    double? taxAmount,
    double? amountExcludingTax,
    double? grossProfit,
    String? paymentStatus,
    String? paymentDate,
    String? remark,
    int? bookId,
    List<String>? voucherImages,
    String? createdAt,
    String? updatedAt,
  }) {
    return Income(
      id: id ?? this.id,
      date: date ?? this.date,
      customerName: customerName ?? this.customerName,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      amount: amount ?? this.amount,
      cost: cost ?? this.cost,
      invoiceType: invoiceType ?? this.invoiceType,
      taxRate: taxRate ?? this.taxRate,
      taxAmount: taxAmount ?? this.taxAmount,
      amountExcludingTax: amountExcludingTax ?? this.amountExcludingTax,
      grossProfit: grossProfit ?? this.grossProfit,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentDate: paymentDate ?? this.paymentDate,
      remark: remark ?? this.remark,
      bookId: bookId ?? this.bookId,
      voucherImages: voucherImages ?? this.voucherImages,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
