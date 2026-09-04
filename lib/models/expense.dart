class Expense {
  final int? id;
  final String date; // YYYY-MM-DD
  final double amount;
  final int? expenseTypeId; // 支出类型ID
  final String? expenseTypeName; // 支出类型名称（冗余，方便显示）
  final String? supplierNote; // 供应商/说明（合并字段）
  final String invoiceType; // none/general/special
  final double taxRate;
  final double taxAmount;
  final String paymentStatus; // paid/unpaid
  final String? paymentDate;
  final String? remark;
  final int bookId; // 所属账本ID
  final String createdAt;
  final String updatedAt;

  Expense({
    this.id,
    required this.date,
    required this.amount,
    this.expenseTypeId,
    this.expenseTypeName,
    this.supplierNote,
    this.invoiceType = 'none',
    this.taxRate = 0,
    this.taxAmount = 0,
    this.paymentStatus = 'paid',
    this.paymentDate,
    this.remark,
    this.bookId = 1,
    required this.createdAt,
    required this.updatedAt,
  });

  static Map<String, double> calculateTax({
    required double amount,
    String invoiceType = 'none',
    double taxRate = 0,
  }) {
    double taxAmount = 0;
    if (invoiceType != 'none' && taxRate > 0) {
      taxAmount = amount - amount / (1 + taxRate);
    }
    return {'taxAmount': double.parse(taxAmount.toStringAsFixed(2))};
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'amount': amount,
      'expense_type_id': expenseTypeId,
      'expense_type_name': expenseTypeName,
      'supplier_note': supplierNote,
      'invoice_type': invoiceType,
      'tax_rate': taxRate,
      'tax_amount': taxAmount,
      'payment_status': paymentStatus,
      'payment_date': paymentDate,
      'remark': remark,
      'book_id': bookId,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as int?,
      date: map['date'] as String,
      amount: (map['amount'] as num).toDouble(),
      expenseTypeId: map['expense_type_id'] as int?,
      expenseTypeName: map['expense_type_name'] as String?,
      supplierNote: map['supplier_note'] as String?,
      invoiceType: map['invoice_type'] as String? ?? 'none',
      taxRate: (map['tax_rate'] as num?)?.toDouble() ?? 0,
      taxAmount: (map['tax_amount'] as num?)?.toDouble() ?? 0,
      paymentStatus: map['payment_status'] as String? ?? 'paid',
      paymentDate: map['payment_date'] as String?,
      remark: map['remark'] as String?,
      bookId: (map['book_id'] as num?)?.toInt() ?? 1,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }
}
