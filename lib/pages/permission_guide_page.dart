import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../main.dart';

/// 首次启动权限引导页面
class PermissionGuidePage extends StatefulWidget {
  const PermissionGuidePage({super.key});

  @override
  State<PermissionGuidePage> createState() => _PermissionGuidePageState();
}

class _PermissionGuidePageState extends State<PermissionGuidePage> {
  bool _networkPermission = false;
  bool _storagePermission = false;
  bool _bluetoothPermission = false;
  bool _isLoading = false;

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
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                // Logo和标题
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet,
                          size: 48,
                          color: AppTheme.primaryGold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '个人记账软件',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'v2.1.3',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // 权限说明卡片
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '为了提供完整功能，需要以下权限',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // 网络权限
                      _buildPermissionItem(
                        icon: Icons.wifi,
                        title: '网络访问（WiFi直传）',
                        description: '用于同一WiFi网络下两台设备之间互传记账数据。数据仅在局域网内传输，不会上传到互联网。',
                        value: _networkPermission,
                        onChanged: (v) => setState(() => _networkPermission = v),
                        required: true,
                      ),
                      const Divider(height: 24),
                      // 本地存储权限
                      _buildPermissionItem(
                        icon: Icons.folder,
                        title: '本地文件存储',
                        description: '用于保存记账数据、自动备份文件、导出Excel表格等。所有数据仅保存在您的设备本地，不会上传到任何服务器。',
                        value: _storagePermission,
                        onChanged: (v) => setState(() => _storagePermission = v),
                        required: true,
                      ),
                      const Divider(height: 24),
                      // 蓝牙权限（预留）
                      _buildPermissionItem(
                        icon: Icons.bluetooth,
                        title: '蓝牙（备用传输，即将推出）',
                        description: '用于WiFi不可用时通过蓝牙传输备份文件。当前版本暂未启用，后续版本更新后可用。',
                        value: _bluetoothPermission,
                        onChanged: (v) => setState(() => _bluetoothPermission = v),
                        required: false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // 数据安全说明
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.security, color: Colors.white, size: 24),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '数据安全承诺：所有记账数据仅保存在您的设备本地，应用完全离线可用，不会收集或上传任何个人数据。',
                          style: TextStyle(fontSize: 13, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // SmartScreen提示：仅Windows桌面版显示，手机端不相关故隐藏
                if (Platform.isWindows)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.5)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Windows SmartScreen 提示说明',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '首次运行时，如果Windows弹出"已保护你的电脑"提示，请点击"更多信息"→"仍要运行"即可正常使用。这是因为软件未进行数字签名，不影响软件安全性。',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // 按钮
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _onAgree,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.primaryGold,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      elevation: 5,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGold),
                            ),
                          )
                        : const Text(
                            '全部同意并进入软件',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _isLoading ? null : _onSkip,
                    child: const Text(
                      '稍后在设置中配置',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionItem({
    required IconData icon,
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool required,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.primaryGold.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.primaryGold, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  if (required)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.expenseRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '必需',
                        style: TextStyle(fontSize: 10, color: AppTheme.expenseRed),
                      ),
                    ),
                  Switch(
                    value: value,
                    onChanged: onChanged,
                    activeColor: AppTheme.primaryGold,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _onAgree() async {
    setState(() => _isLoading = true);
    // 保存权限设置
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permission_guide_shown', true);
    await prefs.setBool('permission_network', _networkPermission || true);
    await prefs.setBool('permission_storage', _storagePermission || true);
    await prefs.setBool('permission_bluetooth', _bluetoothPermission);
    // 跳转到主界面
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
    }
  }

  Future<void> _onSkip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permission_guide_shown', true);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
    }
  }
}
