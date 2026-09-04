import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'theme/app_theme.dart';
import 'pages/home_page.dart';
import 'pages/income_list_page.dart';
import 'pages/expense_list_page.dart';
import 'pages/income_form_page.dart';
import 'pages/expense_form_page.dart';
import 'pages/stats_page.dart';
import 'pages/customer_list_page.dart';
import 'pages/tax_center_page.dart';
import 'pages/permission_guide_page.dart';
import 'widgets/bottom_nav.dart';
import 'providers/settings_providers.dart';

void main() {
  // 桌面端(Windows/Linux/macOS)sqflite初始化：sqflite默认仅支持Android/iOS，桌面端需用FFI
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  // 全局兜底：任何未预料到的界面绘制异常，都用友好提示替代 release 版默认的灰色错误块，
  // 且只替换出错区域，不连累外层主框架与底部导航，避免整屏变灰、无法操作。
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFFFAF6EC),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.sentiment_dissatisfied_outlined, color: AppTheme.primaryGold, size: 42),
            SizedBox(height: 10),
            Text('此区域暂时加载异常', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            SizedBox(height: 6),
            Text('数据没有丢失，请切换其他页面后再回来，或下拉刷新重试', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppTheme.textHint)),
          ]),
        ),
      ),
    );
  };
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(darkModeProvider);
    return MaterialApp(
      title: '个人记账',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      home: const SplashScreen(),
    );
  }
}

/// 启动页：判断是否首次启动，显示权限引导或主界面
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    // 显示品牌启动页，与原生金色启动屏无缝衔接
    await Future.delayed(const Duration(milliseconds: 1200));
    final prefs = await SharedPreferences.getInstance();
    final guideShown = prefs.getBool('permission_guide_shown') ?? false;
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => guideShown ? const MainShell() : const PermissionGuidePage(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB8860B), Color(0xFF8B6914)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  size: 56,
                  color: AppTheme.primaryGold,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '个人记账',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '安全 · 离线 · 高效',
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
              const SizedBox(height: 40),
              const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    HomePage(),
    IncomeListPage(),
    ExpenseListPage(),
    CustomerListPage(),
    TaxCenterPage(),
    StatsPage(),
  ];

  void _onAdd() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('记一笔', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const IncomeFormPage()));
                      },
                      icon: const Icon(Icons.arrow_downward),
                      label: const Text('记收入'),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.incomeGreen),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseFormPage()));
                      },
                      icon: const Icon(Icons.arrow_upward),
                      label: const Text('记支出'),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.expenseRed),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: BottomNav(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        onAdd: _onAdd,
        showNotch: _currentIndex == 0, // 仅首页保留中间圆形加号缺口
      ),
      // 中间圆形加号仅在首页显示；其他页面用各页面右上角绿色加号新增
      floatingActionButton: _currentIndex == 0 ? AddFAB(onPressed: _onAdd) : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}
