import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';
import '../models/book.dart';

// 当前账本ID
final currentBookIdProvider = StateNotifierProvider<CurrentBookNotifier, int>((ref) {
  return CurrentBookNotifier();
});

class CurrentBookNotifier extends StateNotifier<int> {
  CurrentBookNotifier() : super(1) {
    _loadCurrentBook();
  }

  Future<void> _loadCurrentBook() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getInt('current_book_id');
    if (savedId != null) {
      state = savedId;
    } else {
      // 获取默认账本
      final defaultBook = await DatabaseService.instance.getDefaultBook();
      if (defaultBook != null) {
        state = defaultBook.id ?? 1;
      }
    }
  }

  Future<void> setCurrentBook(int bookId) async {
    state = bookId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('current_book_id', bookId);
  }
}

// 账本列表
final booksProvider = FutureProvider<List<Book>>((ref) async {
  return await DatabaseService.instance.getBooks();
});

// 深色模式
final darkModeProvider = StateNotifierProvider<DarkModeNotifier, bool>((ref) {
  return DarkModeNotifier();
});

class DarkModeNotifier extends StateNotifier<bool> {
  DarkModeNotifier() : super(false) {
    _loadDarkMode();
  }

  Future<void> _loadDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('dark_mode') ?? false;
  }

  Future<void> toggleDarkMode() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', state);
  }

  Future<void> setDarkMode(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', value);
  }
}

// 自动备份开关
final autoBackupProvider = StateNotifierProvider<AutoBackupNotifier, bool>((ref) {
  return AutoBackupNotifier();
});

class AutoBackupNotifier extends StateNotifier<bool> {
  AutoBackupNotifier() : super(true) {
    _loadAutoBackup();
  }

  Future<void> _loadAutoBackup() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('auto_backup') ?? true;
  }

  Future<void> toggleAutoBackup() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_backup', state);
  }
}

// 备份容量上限（MB）
final backupLimitProvider = StateNotifierProvider<BackupLimitNotifier, int>((ref) {
  return BackupLimitNotifier();
});

class BackupLimitNotifier extends StateNotifier<int> {
  BackupLimitNotifier() : super(1024) {
    _loadLimit();
  }

  Future<void> _loadLimit() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt('backup_limit_mb') ?? 1024;
  }

  Future<void> setLimit(int mb) async {
    state = mb;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('backup_limit_mb', mb);
  }
}

// 自动备份频率（天数：0=每次记账后，1=每天，3=每3天，7=每周，30=每月，-1=关闭）
final backupFrequencyProvider = StateNotifierProvider<BackupFrequencyNotifier, int>((ref) {
  return BackupFrequencyNotifier();
});

class BackupFrequencyNotifier extends StateNotifier<int> {
  BackupFrequencyNotifier() : super(0) {
    _loadFrequency();
  }

  Future<void> _loadFrequency() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt('backup_frequency_days') ?? 0;
  }

  Future<void> setFrequency(int days) async {
    state = days;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('backup_frequency_days', days);
  }
}

// 金额隐私遮罩
final amountPrivacyProvider = StateNotifierProvider<AmountPrivacyNotifier, bool>((ref) {
  return AmountPrivacyNotifier();
});

class AmountPrivacyNotifier extends StateNotifier<bool> {
  AmountPrivacyNotifier() : super(false) {
    _loadPrivacy();
  }

  Future<void> _loadPrivacy() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('amount_privacy') ?? false;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('amount_privacy', state);
  }
}

// 纳税人身份
final taxpayerTypeProvider = StateNotifierProvider<TaxpayerTypeNotifier, String>((ref) {
  return TaxpayerTypeNotifier();
});

class TaxpayerTypeNotifier extends StateNotifier<String> {
  TaxpayerTypeNotifier() : super('general') {
    _loadType();
  }

  Future<void> _loadType() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('taxpayer_type') ?? 'general';
  }

  Future<void> setType(String type) async {
    state = type;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('taxpayer_type', type);
  }
}

// 回收站数量（用于显示角标）
final recycleBinCountProvider = FutureProvider<int>((ref) async {
  final items = await DatabaseService.instance.getRecycleItems();
  return items.length;
});

// 普票默认税率预设（默认3%）
final generalTaxRateProvider = StateNotifierProvider<TaxRateNotifier, double>((ref) {
  return TaxRateNotifier(key: 'general_tax_rate', defaultValue: 0.03);
});

// 专票默认税率预设（默认13%）
final specialTaxRateProvider = StateNotifierProvider<TaxRateNotifier, double>((ref) {
  return TaxRateNotifier(key: 'special_tax_rate', defaultValue: 0.13);
});

class TaxRateNotifier extends StateNotifier<double> {
  final String key;
  final double defaultValue;
  TaxRateNotifier({required this.key, required this.defaultValue}) : super(defaultValue) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getDouble(key) ?? defaultValue;
  }

  Future<void> setRate(double rate) async {
    state = rate;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, rate);
  }
}
