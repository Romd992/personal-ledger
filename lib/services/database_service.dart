import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import '../models/income.dart';
import '../models/expense.dart';
import '../models/customer.dart';
import '../models/expense_type.dart';
import '../models/book.dart';
import '../models/recycle_item.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final fullPath = path.join(dbPath, 'personal_ledger.db');
    return await openDatabase(
      fullPath,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // 新增账本表
      await db.execute('''
        CREATE TABLE IF NOT EXISTS books (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          is_default INTEGER DEFAULT 0,
          sort_order INTEGER DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');
      // 创建默认账本
      final now = DateTime.now().toIso8601String().substring(0, 19).replaceAll('T', ' ');
      await db.insert('books', {'name': '默认账本', 'is_default': 1, 'sort_order': 0, 'created_at': now});
      // 新增回收站表
      await db.execute('''
        CREATE TABLE IF NOT EXISTS recycle_bin (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          record_type TEXT NOT NULL,
          record_id INTEGER NOT NULL,
          record_json TEXT NOT NULL,
          deleted_at TEXT NOT NULL,
          expire_at TEXT NOT NULL
        )
      ''');
      // 给收入表添加book_id字段
      try {
        await db.execute('ALTER TABLE incomes ADD COLUMN book_id INTEGER DEFAULT 1');
      } catch (_) {}
      // 给支出表添加book_id字段
      try {
        await db.execute('ALTER TABLE expenses ADD COLUMN book_id INTEGER DEFAULT 1');
      } catch (_) {}
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // 收入表
    await db.execute('''
      CREATE TABLE incomes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        customer_name TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity REAL,
        unit_price REAL,
        amount REAL NOT NULL,
        cost REAL DEFAULT 0,
        invoice_type TEXT DEFAULT 'none',
        tax_rate REAL DEFAULT 0,
        tax_amount REAL DEFAULT 0,
        amount_excluding_tax REAL DEFAULT 0,
        gross_profit REAL DEFAULT 0,
        payment_status TEXT DEFAULT 'paid',
        payment_date TEXT,
        remark TEXT,
        book_id INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 支出表
    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        amount REAL NOT NULL,
        expense_type_id INTEGER,
        expense_type_name TEXT,
        supplier_note TEXT,
        invoice_type TEXT DEFAULT 'none',
        tax_rate REAL DEFAULT 0,
        tax_amount REAL DEFAULT 0,
        payment_status TEXT DEFAULT 'paid',
        payment_date TEXT,
        remark TEXT,
        book_id INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 客户表
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        contact TEXT,
        phone TEXT,
        address TEXT,
        remark TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 支出类型表
    await db.execute('''
      CREATE TABLE expense_types (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        icon TEXT DEFAULT 'category',
        sort_order INTEGER DEFAULT 0,
        is_built_in INTEGER DEFAULT 0
      )
    ''');

    // 记账模板表
    await db.execute('''
      CREATE TABLE templates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // 备份记录表
    await db.execute('''
      CREATE TABLE backups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        file_size INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // 账本表
    await db.execute('''
      CREATE TABLE books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        is_default INTEGER DEFAULT 0,
        sort_order INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // 回收站表
    await db.execute('''
      CREATE TABLE recycle_bin (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        record_type TEXT NOT NULL,
        record_id INTEGER NOT NULL,
        record_json TEXT NOT NULL,
        deleted_at TEXT NOT NULL,
        expire_at TEXT NOT NULL
      )
    ''');

    // 初始化内置支出类型
    for (var type in ExpenseType.builtInTypes) {
      await db.insert('expense_types', type.toMap());
    }

    // 创建默认账本
    final now = DateTime.now().toIso8601String().substring(0, 19).replaceAll('T', ' ');
    await db.insert('books', {'name': '默认账本', 'is_default': 1, 'sort_order': 0, 'created_at': now});
  }

  // ==================== 账本 CRUD ====================
  Future<int> insertBook(Book book) async {
    final db = await database;
    return await db.insert('books', book.toMap());
  }

  Future<List<Book>> getBooks() async {
    final db = await database;
    final maps = await db.query('books', orderBy: 'sort_order ASC, id ASC');
    return maps.map((e) => Book.fromMap(e)).toList();
  }

  Future<Book?> getDefaultBook() async {
    final db = await database;
    final maps = await db.query('books', where: 'is_default = 1', limit: 1);
    if (maps.isEmpty) return null;
    return Book.fromMap(maps.first);
  }

  Future<int> updateBook(Book book) async {
    final db = await database;
    return await db.update('books', book.toMap(), where: 'id = ?', whereArgs: [book.id]);
  }

  Future<int> deleteBook(int id) async {
    final db = await database;
    // 默认账本不可删除
    return await db.delete('books', where: 'id = ? AND is_default = 0', whereArgs: [id]);
  }

  // ==================== 回收站 CRUD ====================
  Future<int> insertRecycleItem(RecycleItem item) async {
    final db = await database;
    return await db.insert('recycle_bin', item.toMap());
  }

  Future<List<RecycleItem>> getRecycleItems() async {
    final db = await database;
    // 先清理过期的
    final now = DateTime.now().toIso8601String().substring(0, 19).replaceAll('T', ' ');
    await db.delete('recycle_bin', where: 'expire_at < ?', whereArgs: [now]);
    final maps = await db.query('recycle_bin', orderBy: 'deleted_at DESC');
    return maps.map((e) => RecycleItem.fromMap(e)).toList();
  }

  Future<int> deleteRecycleItem(int id) async {
    final db = await database;
    return await db.delete('recycle_bin', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> clearRecycleBin() async {
    final db = await database;
    return await db.delete('recycle_bin');
  }

  // 还原收入记录
  Future<void> restoreIncome(RecycleItem item) async {
    final db = await database;
    final data = jsonDecode(item.recordJson) as Map<String, dynamic>;
    data.remove('id'); // 移除旧ID，让数据库自动生成新ID
    await db.insert('incomes', Map<String, dynamic>.from(data));
    await db.delete('recycle_bin', where: 'id = ?', whereArgs: [item.id]);
  }

  // 还原支出记录
  Future<void> restoreExpense(RecycleItem item) async {
    final db = await database;
    final data = jsonDecode(item.recordJson) as Map<String, dynamic>;
    data.remove('id');
    await db.insert('expenses', Map<String, dynamic>.from(data));
    await db.delete('recycle_bin', where: 'id = ?', whereArgs: [item.id]);
  }

  // ==================== 收入 CRUD ====================
  Future<int> insertIncome(Income income) async {
    final db = await database;
    return await db.insert('incomes', income.toMap());
  }

  Future<List<Income>> getIncomes({String? startDate, String? endDate, String? customerName, String? paymentStatus, String? invoiceType, String? keyword, int? bookId}) async {
    final db = await database;
    String where = '1=1';
    List<dynamic> args = [];
    if (bookId != null) { where += ' AND book_id = ?'; args.add(bookId); }
    if (startDate != null) { where += ' AND date >= ?'; args.add(startDate); }
    if (endDate != null) { where += ' AND date <= ?'; args.add(endDate); }
    if (customerName != null) { where += ' AND customer_name = ?'; args.add(customerName); }
    if (paymentStatus != null) { where += ' AND payment_status = ?'; args.add(paymentStatus); }
    if (invoiceType != null) { where += ' AND invoice_type = ?'; args.add(invoiceType); }
    if (keyword != null && keyword.isNotEmpty) {
      where += ' AND (customer_name LIKE ? OR product_name LIKE ? OR remark LIKE ?)';
      args.add('%$keyword%'); args.add('%$keyword%'); args.add('%$keyword%');
    }
    final maps = await db.query('incomes', where: where, whereArgs: args, orderBy: 'date DESC, id DESC');
    return maps.map((e) => Income.fromMap(e)).toList();
  }

  Future<int> updateIncome(Income income) async {
    final db = await database;
    return await db.update('incomes', income.toMap(), where: 'id = ?', whereArgs: [income.id]);
  }

  // 删除收入：移入回收站而非真正删除
  Future<int> deleteIncome(int id) async {
    final db = await database;
    final maps = await db.query('incomes', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      final now = DateTime.now();
      final deletedAt = now.toIso8601String().substring(0, 19).replaceAll('T', ' ');
      final expireAt = now.add(const Duration(days: 30)).toIso8601String().substring(0, 19).replaceAll('T', ' ');
      await db.insert('recycle_bin', {
        'record_type': 'income',
        'record_id': id,
        'record_json': jsonEncode(maps.first),
        'deleted_at': deletedAt,
        'expire_at': expireAt,
      });
    }
    return await db.delete('incomes', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== 支出 CRUD ====================
  Future<int> insertExpense(Expense expense) async {
    final db = await database;
    return await db.insert('expenses', expense.toMap());
  }

  Future<List<Expense>> getExpenses({String? startDate, String? endDate, int? expenseTypeId, String? paymentStatus, String? invoiceType, String? keyword, int? bookId}) async {
    final db = await database;
    String where = '1=1';
    List<dynamic> args = [];
    if (bookId != null) { where += ' AND book_id = ?'; args.add(bookId); }
    if (startDate != null) { where += ' AND date >= ?'; args.add(startDate); }
    if (endDate != null) { where += ' AND date <= ?'; args.add(endDate); }
    if (expenseTypeId != null) { where += ' AND expense_type_id = ?'; args.add(expenseTypeId); }
    if (paymentStatus != null) { where += ' AND payment_status = ?'; args.add(paymentStatus); }
    if (invoiceType != null) { where += ' AND invoice_type = ?'; args.add(invoiceType); }
    if (keyword != null && keyword.isNotEmpty) {
      where += ' AND (supplier_note LIKE ? OR remark LIKE ? OR expense_type_name LIKE ?)';
      args.add('%$keyword%'); args.add('%$keyword%'); args.add('%$keyword%');
    }
    final maps = await db.query('expenses', where: where, whereArgs: args, orderBy: 'date DESC, id DESC');
    return maps.map((e) => Expense.fromMap(e)).toList();
  }

  Future<int> updateExpense(Expense expense) async {
    final db = await database;
    return await db.update('expenses', expense.toMap(), where: 'id = ?', whereArgs: [expense.id]);
  }

  // 删除支出：移入回收站
  Future<int> deleteExpense(int id) async {
    final db = await database;
    final maps = await db.query('expenses', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      final now = DateTime.now();
      final deletedAt = now.toIso8601String().substring(0, 19).replaceAll('T', ' ');
      final expireAt = now.add(const Duration(days: 30)).toIso8601String().substring(0, 19).replaceAll('T', ' ');
      await db.insert('recycle_bin', {
        'record_type': 'expense',
        'record_id': id,
        'record_json': jsonEncode(maps.first),
        'deleted_at': deletedAt,
        'expire_at': expireAt,
      });
    }
    return await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== 客户 CRUD ====================
  Future<int> insertCustomer(Customer customer) async {
    final db = await database;
    return await db.insert('customers', customer.toMap());
  }

  Future<List<Customer>> getCustomers({String? keyword}) async {
    final db = await database;
    final maps = keyword != null && keyword.isNotEmpty
        ? await db.query('customers', where: 'name LIKE ?', whereArgs: ['%$keyword%'], orderBy: 'name ASC')
        : await db.query('customers', orderBy: 'name ASC');
    return maps.map((e) => Customer.fromMap(e)).toList();
  }

  Future<List<String>> getCustomerNames({String? keyword}) async {
    final db = await database;
    final maps = keyword != null && keyword.isNotEmpty
        ? await db.query('customers', columns: ['name'], where: 'name LIKE ?', whereArgs: ['%$keyword%'], orderBy: 'name ASC')
        : await db.query('customers', columns: ['name'], orderBy: 'name ASC');
    final incomeMaps = await db.rawQuery('SELECT DISTINCT customer_name FROM incomes ORDER BY customer_name ASC');
    final Set<String> names = {};
    for (var m in maps) { names.add(m['name'] as String); }
    for (var m in incomeMaps) { names.add(m['customer_name'] as String); }
    final result = names.toList()..sort();
    if (keyword != null && keyword.isNotEmpty) {
      return result.where((n) => n.contains(keyword)).toList();
    }
    return result;
  }

  Future<int> updateCustomer(Customer customer) async {
    final db = await database;
    return await db.update('customers', customer.toMap(), where: 'id = ?', whereArgs: [customer.id]);
  }

  Future<int> deleteCustomer(int id) async {
    final db = await database;
    return await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== 支出类型 CRUD ====================
  Future<int> insertExpenseType(ExpenseType type) async {
    final db = await database;
    return await db.insert('expense_types', type.toMap());
  }

  Future<List<ExpenseType>> getExpenseTypes() async {
    final db = await database;
    final maps = await db.query('expense_types', orderBy: 'sort_order ASC, id ASC');
    return maps.map((e) => ExpenseType.fromMap(e)).toList();
  }

  Future<int> updateExpenseType(ExpenseType type) async {
    final db = await database;
    return await db.update('expense_types', type.toMap(), where: 'id = ?', whereArgs: [type.id]);
  }

  Future<int> deleteExpenseType(int id) async {
    final db = await database;
    return await db.delete('expense_types', where: 'id = ? AND is_built_in = 0', whereArgs: [id]);
  }

  // ==================== 记账模板 CRUD ====================
  Future<int> insertTemplate(String type, String name, String content) async {
    final db = await database;
    final now = DateTime.now().toIso8601String().substring(0, 19).replaceAll('T', ' ');
    return await db.insert('templates', {'type': type, 'name': name, 'content': content, 'created_at': now});
  }

  Future<List<Map<String, dynamic>>> getTemplates({String? type}) async {
    final db = await database;
    if (type != null) {
      return await db.query('templates', where: 'type = ?', whereArgs: [type], orderBy: 'created_at DESC');
    }
    return await db.query('templates', orderBy: 'created_at DESC');
  }

  Future<int> deleteTemplate(int id) async {
    final db = await database;
    return await db.delete('templates', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== 统计查询 ====================
  Future<Map<String, double>> getIncomeStats({String? startDate, String? endDate, int? bookId}) async {
    final db = await database;
    String where = '1=1';
    List<dynamic> args = [];
    if (bookId != null) { where += ' AND book_id = ?'; args.add(bookId); }
    if (startDate != null) { where += ' AND date >= ?'; args.add(startDate); }
    if (endDate != null) { where += ' AND date <= ?'; args.add(endDate); }
    final result = await db.rawQuery('''
      SELECT
        COALESCE(SUM(amount), 0) as total_amount,
        COALESCE(SUM(amount_excluding_tax), 0) as total_excluding_tax,
        COALESCE(SUM(cost), 0) as total_cost,
        COALESCE(SUM(tax_amount), 0) as total_tax,
        COALESCE(SUM(gross_profit), 0) as total_gross_profit,
        COALESCE(SUM(CASE WHEN payment_status = 'paid' THEN amount ELSE 0 END), 0) as paid_amount,
        COALESCE(SUM(CASE WHEN payment_status = 'unpaid' THEN amount ELSE 0 END), 0) as unpaid_amount
      FROM incomes WHERE $where
    ''', args);
    final row = result.first;
    return {
      'totalAmount': (row['total_amount'] as num).toDouble(),
      'totalExcludingTax': (row['total_excluding_tax'] as num).toDouble(),
      'totalCost': (row['total_cost'] as num).toDouble(),
      'totalTax': (row['total_tax'] as num).toDouble(),
      'totalGrossProfit': (row['total_gross_profit'] as num).toDouble(),
      'paidAmount': (row['paid_amount'] as num).toDouble(),
      'unpaidAmount': (row['unpaid_amount'] as num).toDouble(),
    };
  }

  Future<Map<String, double>> getExpenseStats({String? startDate, String? endDate, int? bookId}) async {
    final db = await database;
    String where = '1=1';
    List<dynamic> args = [];
    if (bookId != null) { where += ' AND book_id = ?'; args.add(bookId); }
    if (startDate != null) { where += ' AND date >= ?'; args.add(startDate); }
    if (endDate != null) { where += ' AND date <= ?'; args.add(endDate); }
    final result = await db.rawQuery('''
      SELECT
        COALESCE(SUM(amount), 0) as total_amount,
        COALESCE(SUM(tax_amount), 0) as total_tax,
        COALESCE(SUM(CASE WHEN payment_status = 'paid' THEN amount ELSE 0 END), 0) as paid_amount,
        COALESCE(SUM(CASE WHEN payment_status = 'unpaid' THEN amount ELSE 0 END), 0) as unpaid_amount
      FROM expenses WHERE $where
    ''', args);
    final row = result.first;
    return {
      'totalAmount': (row['total_amount'] as num).toDouble(),
      'totalTax': (row['total_tax'] as num).toDouble(),
      'paidAmount': (row['paid_amount'] as num).toDouble(),
      'unpaidAmount': (row['unpaid_amount'] as num).toDouble(),
    };
  }

  // 月度趋势数据
  Future<List<Map<String, dynamic>>> getMonthlyTrend({int months = 12, int? bookId}) async {
    final db = await database;
    String bookFilter = '';
    List<dynamic> args = [];
    if (bookId != null) {
      bookFilter = ' WHERE book_id = ?';
      args.add(bookId);
    }
    final result = await db.rawQuery('''
      SELECT
        substr(date, 1, 7) as month,
        COALESCE(SUM(CASE WHEN type='income' THEN amount ELSE 0 END), 0) as income,
        COALESCE(SUM(CASE WHEN type='expense' THEN amount ELSE 0 END), 0) as expense
      FROM (
        SELECT date, amount, book_id, 'income' as type FROM incomes
        UNION ALL
        SELECT date, amount, book_id, 'expense' as type FROM expenses
      )
      $bookFilter
      GROUP BY month
      ORDER BY month DESC
      LIMIT $months
    ''', args);
    // 关键修复：SQLite 的 SUM 在“某列整月为0（如只记收入未记支出）”时会返回 int，
    // 直接 as double 会在绘制时抛 int!=double 异常导致 release 版整页变灰。
    // 这里统一清洗为 double，month 统一为 String，从源头保证类型稳定。
    return result.reversed.map((row) => <String, dynamic>{
      'month': '${row['month']}',
      'income': (row['income'] as num).toDouble(),
      'expense': (row['expense'] as num).toDouble(),
    }).toList();
  }

  // ==================== 数据导出/导入 ====================
  Future<Map<String, dynamic>> exportAllData() async {
    final db = await database;
    final incomes = await db.query('incomes', orderBy: 'id ASC');
    final expenses = await db.query('expenses', orderBy: 'id ASC');
    final customers = await db.query('customers', orderBy: 'id ASC');
    final expenseTypes = await db.query('expense_types', orderBy: 'id ASC');
    final templates = await db.query('templates', orderBy: 'id ASC');
    final books = await db.query('books', orderBy: 'id ASC');
    return {
      'version': '2.0',
      'exportTime': DateTime.now().toIso8601String(),
      'data': {
        'incomes': incomes,
        'expenses': expenses,
        'customers': customers,
        'expense_types': expenseTypes,
        'templates': templates,
        'books': books,
      },
      'stats': {
        'incomeCount': incomes.length,
        'expenseCount': expenses.length,
        'customerCount': customers.length,
        'bookCount': books.length,
      },
    };
  }

  Future<int> importAllData(Map<String, dynamic> data, {bool clearExisting = true}) async {
    final db = await database;
    int imported = 0;
    await db.transaction((txn) async {
      if (clearExisting) {
        await txn.delete('incomes');
        await txn.delete('expenses');
        await txn.delete('customers');
        await txn.delete('expense_types');
        await txn.delete('templates');
        await txn.delete('books');
      }
      final tables = data['data'] as Map<String, dynamic>;
      for (var entry in tables.entries) {
        final tableName = entry.key;
        final rows = entry.value as List;
        for (var row in rows) {
          try {
            await txn.insert(tableName, Map<String, dynamic>.from(row));
            imported++;
          } catch (_) {}
        }
      }
    });
    return imported;
  }
}
