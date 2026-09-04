import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database_service.dart';
import '../models/income.dart';
import '../models/expense.dart';
import '../models/expense_type.dart';
import 'settings_providers.dart';

// 数据库服务Provider
final databaseProvider = Provider<DatabaseService>((ref) => DatabaseService.instance);

// 收入列表Provider（带筛选条件）
class IncomeFilter {
  final String? startDate;
  final String? endDate;
  final String? customerName;
  final String? paymentStatus;
  final String? invoiceType;
  final String? keyword;
  const IncomeFilter({this.startDate, this.endDate, this.customerName, this.paymentStatus, this.invoiceType, this.keyword});
}

final incomeFilterProvider = StateProvider<IncomeFilter>((ref) => const IncomeFilter());

final incomesProvider = FutureProvider<List<Income>>((ref) async {
  final filter = ref.watch(incomeFilterProvider);
  final bookId = ref.watch(currentBookIdProvider);
  ref.watch(refreshTriggerProvider);
  return DatabaseService.instance.getIncomes(
    startDate: filter.startDate,
    endDate: filter.endDate,
    customerName: filter.customerName,
    paymentStatus: filter.paymentStatus,
    invoiceType: filter.invoiceType,
    keyword: filter.keyword,
    bookId: bookId,
  );
});

// 支出列表Provider
class ExpenseFilter {
  final String? startDate;
  final String? endDate;
  final int? expenseTypeId;
  final String? paymentStatus;
  final String? keyword;
  const ExpenseFilter({this.startDate, this.endDate, this.expenseTypeId, this.paymentStatus, this.keyword});
}

final expenseFilterProvider = StateProvider<ExpenseFilter>((ref) => const ExpenseFilter());

final expensesProvider = FutureProvider<List<Expense>>((ref) async {
  final filter = ref.watch(expenseFilterProvider);
  final bookId = ref.watch(currentBookIdProvider);
  ref.watch(refreshTriggerProvider);
  return DatabaseService.instance.getExpenses(
    startDate: filter.startDate,
    endDate: filter.endDate,
    expenseTypeId: filter.expenseTypeId,
    paymentStatus: filter.paymentStatus,
    keyword: filter.keyword,
    bookId: bookId,
  );
});

// 支出类型Provider
final expenseTypesProvider = FutureProvider<List<ExpenseType>>((ref) async {
  return DatabaseService.instance.getExpenseTypes();
});

// 客户名称联想Provider
final customerNamesProvider = FutureProvider.family<List<String>, String>((ref, keyword) async {
  return DatabaseService.instance.getCustomerNames(keyword: keyword.isEmpty ? null : keyword);
});

// 统计数据Provider
final incomeStatsProvider = FutureProvider.family<Map<String, double>, IncomeFilter>((ref, filter) async {
  final bookId = ref.watch(currentBookIdProvider);
  return DatabaseService.instance.getIncomeStats(startDate: filter.startDate, endDate: filter.endDate, bookId: bookId);
});

final expenseStatsProvider = FutureProvider.family<Map<String, double>, ExpenseFilter>((ref, filter) async {
  final bookId = ref.watch(currentBookIdProvider);
  return DatabaseService.instance.getExpenseStats(startDate: filter.startDate, endDate: filter.endDate, bookId: bookId);
});

// 刷新数据的Provider（用于插入/更新/删除后刷新列表）
final refreshTriggerProvider = StateProvider<int>((ref) => 0);
