import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import '../theme/app_theme.dart';
import '../providers/settings_providers.dart';
import '../services/update_service.dart';
import '../services/feedback_service.dart';
import '../services/data_migration_service.dart';
import '../services/platform_file_service.dart';
import '../services/database_service.dart';
import 'book_manage_page.dart';
import 'recycle_bin_page.dart';
import 'backup_export_page.dart';
import 'import_backup_page.dart';
import 'template_manage_page.dart';
import 'wifi_transfer_page.dart';
import 'bluetooth_transfer_page.dart';
import 'expense_type_manage_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _isCheckingUpdate = false;

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(darkModeProvider);
    final autoBackup = ref.watch(autoBackupProvider);
    final backupLimit = ref.watch(backupLimitProvider);
    final amountPrivacy = ref.watch(amountPrivacyProvider);
    final taxpayerType = ref.watch(taxpayerTypeProvider);
    final generalRate = ref.watch(generalTaxRateProvider);
    final specialRate = ref.watch(specialTaxRateProvider);
    final recycleCount = ref.watch(recycleBinCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        // 恢复左上角返回按钮，可原路返回上一级
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        children: [
          // 偏好设置
          _buildSectionHeader('偏好设置'),
          _buildSwitchTile(
            icon: Icons.dark_mode,
            title: '深色模式',
            subtitle: '保护眼睛，夜间使用更舒适',
            value: isDark,
            onChanged: (v) => ref.read(darkModeProvider.notifier).toggleDarkMode(),
          ),
          _buildSwitchTile(
            icon: Icons.visibility_off,
            title: '金额隐私',
            subtitle: '首页金额显示为 ****',
            value: amountPrivacy,
            onChanged: (v) => ref.read(amountPrivacyProvider.notifier).toggle(),
          ),
          _buildSwitchTile(
            icon: Icons.backup,
            title: '自动备份',
            subtitle: autoBackup ? '已开启，按设定频率自动备份' : '已关闭',
            value: autoBackup,
            onChanged: (v) => ref.read(autoBackupProvider.notifier).toggleAutoBackup(),
          ),
          _buildListTile(
            icon: Icons.schedule,
            title: '自动备份频率',
            subtitle: _getBackupFrequencyText(ref.watch(backupFrequencyProvider)),
            onTap: () => _showBackupFrequencyDialog(context, ref),
          ),
          _buildListTile(
            icon: Icons.folder_open,
            title: '查看备份存储位置',
            subtitle: '点击打开手机文件管理器中的备份文件夹',
            onTap: () => _openBackupFolder(context),
          ),
          _buildListTile(
            icon: Icons.storage,
            title: '备份容量上限',
            subtitle: '当前上限：${backupLimit}MB，超过自动删除最旧备份',
            onTap: () => _showBackupLimitDialog(context, ref, backupLimit),
          ),
          const Divider(height: 1),

          // 税务设置
          _buildSectionHeader('税务设置'),
          _buildListTile(
            icon: Icons.account_balance,
            title: '纳税人身份',
            subtitle: taxpayerType == 'general' ? '一般纳税人' : '小规模纳税人',
            onTap: () => _showTaxpayerDialog(context, ref, taxpayerType),
          ),
          _buildListTile(
            icon: Icons.percent,
            title: '默认税率预设',
            subtitle: '普票 ${(generalRate*100).toStringAsFixed(generalRate*100 % 1 == 0 ? 0 : 1)}% · 专票 ${(specialRate*100).toStringAsFixed(specialRate*100 % 1 == 0 ? 0 : 1)}%，记账选发票类型时自动套用',
            onTap: () => _showTaxRatePresetDialog(context, ref, generalRate, specialRate),
          ),
          const Divider(height: 1),

          // 数据管理
          _buildSectionHeader('数据管理'),
          _buildListTile(
            icon: Icons.book,
            title: '账本管理',
            subtitle: '创建多个账本，数据独立',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookManagePage())),
          ),
          _buildListTile(
            icon: Icons.delete_sweep,
            title: '回收站',
            subtitle: '已删除记录保留30天，可还原',
            trailing: recycleCount.when(
              data: (count) => count > 0 ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppTheme.expenseRed, borderRadius: BorderRadius.circular(10)),
                child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 12)),
              ) : null,
              loading: () => null,
              error: (_, __) => null,
            ),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecycleBinPage())),
          ),
          _buildListTile(
            icon: Icons.import_export,
            title: '备份与导出',
            subtitle: '导出Excel/JSON备份，导入数据',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupExportPage())),
          ),
          _buildListTile(
            icon: Icons.wifi,
            title: '多设备同步',
            subtitle: 'WiFi局域网直传数据',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WifiTransferPage())),
          ),
          _buildListTile(
            icon: Icons.bluetooth,
            title: '蓝牙互传',
            subtitle: '通过蓝牙传输加密备份文件',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BluetoothTransferPage())),
          ),
          _buildListTile(
            icon: Icons.swap_horiz,
            title: '数据迁移助手',
            subtitle: '一键打包全部数据，新设备一键恢复（.ledger加密）',
            onTap: () => _showDataMigrationDialog(context),
          ),
          const Divider(height: 1),

          // 记账设置
          _buildSectionHeader('记账设置'),
          _buildListTile(
            icon: Icons.note,
            title: '记账模板',
            subtitle: '管理常用记账模板，快速填入',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TemplateManagePage())),
          ),
          _buildListTile(
            icon: Icons.category,
            title: '支出类型管理',
            subtitle: '自定义支出分类',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseTypeManagePage())),
          ),
          const Divider(height: 1),

          // 关于
          _buildSectionHeader('关于与反馈'),
          _buildListTile(
            icon: Icons.feedback_outlined,
            title: '意见反馈',
            subtitle: '遇到问题或有建议？App内直接提交，无需邮箱',
            onTap: () => _showFeedbackDialog(context),
          ),
          _buildListTile(
            icon: Icons.info_outline,
            title: '关于本软件',
            subtitle: '简帐 v${UpdateService.currentVersionName}',
            onTap: () => _showAboutDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.system_update, color: AppTheme.primaryGold),
            title: const Text('检测更新'),
            subtitle: Text(
              _isCheckingUpdate ? '正在检测...' : '当前版本 v${UpdateService.currentVersionName}，点击检测是否有新版本',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: _isCheckingUpdate
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryGold),
                  )
                : const Icon(Icons.chevron_right, color: AppTheme.textHint),
            onTap: _isCheckingUpdate ? null : () => _checkUpdate(context),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
    );
  }

  Widget _buildSwitchTile({required IconData icon, required String title, String? subtitle, required bool value, required ValueChanged<bool> onChanged}) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primaryGold),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 12)) : null,
      trailing: Switch(value: value, onChanged: onChanged, activeColor: AppTheme.primaryGold),
      onTap: () => onChanged(!value),
    );
  }

  Widget _buildListTile({required IconData icon, required String title, String? subtitle, Widget? trailing, required VoidCallback onTap}) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primaryGold),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 12)) : null,
      trailing: trailing ?? const Icon(Icons.chevron_right, color: AppTheme.textHint),
      onTap: onTap,
    );
  }

  void _showBackupLimitDialog(BuildContext context, WidgetRef ref, int currentLimit) {
    final controller = TextEditingController(text: currentLimit.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('备份容量上限'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('设置备份文件总容量上限（MB），超过后自动删除最旧的备份文件。最大1024MB。'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '容量上限（MB）'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              final value = int.tryParse(controller.text) ?? 1024;
              final limit = value.clamp(10, 1024);
              ref.read(backupLimitProvider.notifier).setLimit(limit);
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showTaxpayerDialog(BuildContext context, WidgetRef ref, String currentType) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('纳税人身份'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('一般纳税人'),
              subtitle: const Text('适用13%/9%/6%等税率，可抵扣进项税'),
              value: 'general',
              groupValue: currentType,
              onChanged: (v) {
                if (v != null) ref.read(taxpayerTypeProvider.notifier).setType(v);
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<String>(
              title: const Text('小规模纳税人'),
              subtitle: const Text('适用3%征收率，不可抵扣进项税'),
              value: 'small',
              groupValue: currentType,
              onChanged: (v) {
                if (v != null) ref.read(taxpayerTypeProvider.notifier).setType(v);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  // 默认税率预设：分别设置普票、专票的默认税率
  void _showTaxRatePresetDialog(BuildContext context, WidgetRef ref, double generalRate, double specialRate) {
    // 常用税率快捷选项
    const commonRates = [0.01, 0.03, 0.06, 0.09, 0.13];
    double gRate = generalRate;
    double sRate = specialRate;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Widget rateSelector(String title, double current, ValueChanged<double> onPick) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 6),
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: commonRates.map((r) {
                    final selected = (current - r).abs() < 0.000001;
                    return ChoiceChip(
                      label: Text('${(r*100).toStringAsFixed(r*100 % 1 == 0 ? 0 : 1)}%'),
                      selected: selected,
                      onSelected: (_) => setDialogState(() => onPick(r)),
                    );
                  }).toList()
                    ..add(ChoiceChip(
                      label: const Text('自定义'),
                      selected: !commonRates.any((r) => (current - r).abs() < 0.000001),
                      onSelected: (_) async {
                        final ctrl = TextEditingController(text: (current*100).toString());
                        final res = await showDialog<double>(
                          context: ctx,
                          builder: (dctx) => AlertDialog(
                            title: Text('自定义$title税率'),
                            content: TextField(
                              controller: ctrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(suffixText: '%', hintText: '如：5'),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('取消')),
                              TextButton(onPressed: () => Navigator.pop(dctx, double.tryParse(ctrl.text)), child: const Text('确定')),
                            ],
                          ),
                        );
                        if (res != null && res >= 0 && res <= 100) {
                          setDialogState(() => onPick(res / 100));
                        }
                      },
                    )),
                ),
              ],
            );
          }

          return AlertDialog(
            title: const Text('默认税率预设'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('设置后，记账时选择普票/专票会自动套用对应税率，单据上仍可临时修改。', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  rateSelector('普通发票', gRate, (v) => gRate = v),
                  rateSelector('专用发票', sRate, (v) => sRate = v),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              ElevatedButton(
                onPressed: () {
                  ref.read(generalTaxRateProvider.notifier).setRate(gRate);
                  ref.read(specialTaxRateProvider.notifier).setRate(sRate);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('默认税率已保存')));
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 检测更新
  Future<void> _checkUpdate(BuildContext context) async {
    setState(() => _isCheckingUpdate = true);
    final result = await UpdateService.checkUpdate();
    if (!mounted) return;
    setState(() => _isCheckingUpdate = false);

    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error!), duration: const Duration(seconds: 3)),
      );
      return;
    }

    if (!result.hasUpdate || result.latestVersion == null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('已是最新版本'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前版本：v${UpdateService.currentVersionName}'),
              const SizedBox(height: 8),
              const Text('您的软件已经是最新版本，无需更新。'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定')),
          ],
        ),
      );
      return;
    }

    // 有新版本，显示更新弹窗
    final latest = result.latestVersion!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.system_update, color: AppTheme.primaryGold, size: 24),
            const SizedBox(width: 8),
            const Text('发现新版本'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryGold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'v${latest.versionName}（${latest.versionCode > UpdateService.currentVersionCode ? '新版本' : ''}）',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryGold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('更新说明：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            if (latest.releaseNotes.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Text(
                    latest.releaseNotes,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
              )
            else
              const Text('暂无更新说明', style: TextStyle(fontSize: 13, color: AppTheme.textHint)),
            const SizedBox(height: 12),
            const Text(
              '点击"立即下载"将跳转到浏览器下载最新版APK，下载后覆盖安装即可保留所有数据。',
              style: TextStyle(fontSize: 11, color: AppTheme.textHint),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后再说'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final uri = Uri.parse(latest.downloadUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('无法打开下载链接，请手动复制链接到浏览器下载')),
                  );
                }
              }
            },
            icon: const Icon(Icons.download),
            label: const Text('立即下载'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
          ),
        ],
      ),
    );
  }

  /// 显示反馈对话框（App内直接提交到企业微信）
  void _showFeedbackDialog(BuildContext context) {
    final contentController = TextEditingController();
    final contactController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.feedback, color: AppTheme.primaryGold, size: 22),
                const SizedBox(width: 8),
                const Text('意见反馈'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '请描述您遇到的问题或建议，我们会尽快处理。',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contentController,
                    maxLines: 5,
                    minLines: 3,
                    decoration: const InputDecoration(
                      labelText: '反馈内容 *',
                      hintText: '请详细描述遇到的问题或改进建议...',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contactController,
                    decoration: const InputDecoration(
                      labelText: '联系方式（选填）',
                      hintText: '手机号/微信/邮箱，方便我们联系您',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '提交后反馈将实时发送到开发者企业微信，您的隐私会受到保护。',
                    style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton.icon(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final content = contentController.text.trim();
                        if (content.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('请输入反馈内容')),
                          );
                          return;
                        }

                        setDialogState(() => isSubmitting = true);

                        final success = await FeedbackService.submitFeedback(
                          content,
                          contact: contactController.text.trim().isEmpty
                              ? null
                              : contactController.text.trim(),
                        );

                        if (!ctx.mounted) return;
                        setDialogState(() => isSubmitting = false);

                        if (success) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('反馈提交成功，感谢您的意见！'),
                              backgroundColor: Colors.green,
                              duration: Duration(seconds: 3),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('提交失败，请检查网络后重试；若网络正常仍失败，说明反馈通道暂时维护中，请稍后再试'),
                              backgroundColor: Colors.red,
                              duration: Duration(seconds: 4),
                            ),
                          );
                        }
                      },
                icon: isSubmitting
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send, size: 18),
                label: Text(isSubmitting ? '提交中...' : '提交反馈'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 获取备份频率文本
  String _getBackupFrequencyText(int days) {
    switch (days) {
      case 0: return '每次记账后立即备份';
      case 1: return '每1天备份一次';
      case 3: return '每3天备份一次';
      case 7: return '每7天备份一次';
      case 30: return '每30天备份一次';
      case -1: return '已关闭自动备份';
      default: return '每$days天备份一次';
    }
  }

  /// 显示备份频率选择对话框
  void _showBackupFrequencyDialog(BuildContext context, WidgetRef ref) {
    final current = ref.read(backupFrequencyProvider);
    final options = [
      {'value': 0, 'label': '每次记账后', 'desc': '每记一笔收入或支出后立即备份'},
      {'value': 1, 'label': '每天', 'desc': '每天首次打开App时自动备份'},
      {'value': 3, 'label': '每3天', 'desc': '每3天自动备份一次'},
      {'value': 7, 'label': '每周', 'desc': '每7天自动备份一次'},
      {'value': 30, 'label': '每月', 'desc': '每30天自动备份一次'},
      {'value': -1, 'label': '关闭', 'desc': '不自动备份，仅手动备份'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自动备份频率'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) {
              final value = opt['value'] as int;
              final selected = current == value;
              return ListTile(
                title: Text(opt['label'] as String),
                subtitle: Text(opt['desc'] as String, style: const TextStyle(fontSize: 11)),
                trailing: selected ? const Icon(Icons.check_circle, color: AppTheme.primaryGold) : const Icon(Icons.radio_button_unchecked),
                onTap: () {
                  ref.read(backupFrequencyProvider.notifier).setFrequency(value);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('备份频率已设置为：${opt['label']}')),
                  );
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ],
      ),
    );
  }

  /// 打开备份文件夹
  Future<void> _openBackupFolder(BuildContext context) async {
    try {
      // 使用统一的外部可见备份目录（文件管理器可直接访问）
      final backupDirEntity = await PlatformFileService.getBackupDirectory();
      final backupDir = backupDirEntity.path;

      // 显示路径
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('备份存储位置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('备份文件保存在以下位置：', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  backupDir,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 8),
              const Text('点击下方按钮可直接跳转到文件管理器中的备份文件夹。', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  // 使用平台适配服务打开文件夹
                  await PlatformFileService.openFolder(backupDir);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('无法自动打开，请手动复制路径到文件管理器查找')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.folder_open),
              label: const Text('打开备份文件夹'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('获取备份路径失败：$e')),
      );
    }
  }

  /// 显示数据迁移对话框
  void _showDataMigrationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.swap_horiz, color: AppTheme.primaryGold),
            SizedBox(width: 8),
            Text('数据迁移助手'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('一键打包全部数据（记账记录、客户档案、支出类型、模板、设置、凭证图片），生成加密的.ledger备份文件。', style: TextStyle(fontSize: 12)),
            SizedBox(height: 8),
            Text('新设备安装后，导入此文件并输入密码即可完全恢复所有数据。', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _showExportMigrationDialog(context);
            },
            icon: const Icon(Icons.file_upload),
            label: const Text('导出备份'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportBackupPage()));
            },
            icon: const Icon(Icons.file_download),
            label: const Text('导入备份'),
          ),
        ],
      ),
    );
  }

  /// 导出数据迁移备份
  Future<void> _showExportMigrationDialog(BuildContext context) async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出加密备份'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('请设置加密密码（至少6位），导入时需要此密码。', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '加密密码 *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '确认密码 *', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final pwd = passwordController.text;
              final confirm = confirmController.text;
              if (pwd.length < 6) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('密码至少6位')));
                return;
              }
              if (pwd != confirm) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('两次密码不一致')));
                return;
              }

              Navigator.pop(ctx);
              // 显示加载
              showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

              try {
                final db = await DatabaseService.instance.database;
                final path = await DataMigrationService.exportFullBackup(password: pwd, db: db);
                if (context.mounted) {
                  Navigator.pop(context); // 关闭加载
                  // 读取文件内容
                  final backupFile = File(path);
                  final bytes = await backupFile.readAsBytes();
                  final fileName = backupFile.uri.pathSegments.last;

                  // 使用平台适配服务保存文件
                  final savedPath = await PlatformFileService.saveFile(
                    fileName: fileName,
                    bytes: bytes,
                    dialogTitle: '导出加密备份',
                  );

                  if (context.mounted) {
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
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('导出失败：$e')),
                  );
                }
              }
            },
            child: const Text('开始导出'),
          ),
        ],
      ),
    );
  }

  /// 导入数据迁移备份
  Future<void> _showImportMigrationDialog(BuildContext context) async {
    final passwordController = TextEditingController();

    // 先选择文件
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ledger'],
      );
      if (result == null || result.files.single.path == null) return;
      final filePath = result.files.single.path!;

      if (!context.mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导入加密备份'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('文件：${filePath.split('/').last}', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              const Text('⚠️ 导入将覆盖当前所有数据，请确认已备份当前数据！', style: TextStyle(fontSize: 12, color: Colors.red)),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: '加密密码 *', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                final pwd = passwordController.text;
                if (pwd.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('请输入密码')));
                  return;
                }

                Navigator.pop(ctx);
                showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

                try {
                  final db = await DatabaseService.instance.database;
                  final result = await DataMigrationService.importFullBackup(
                    ledgerPath: filePath,
                    password: pwd,
                    db: db,
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('导入成功！恢复了${result['tablesRestored']}张表，${result['rowsRestored']}条记录')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('导入失败：$e')),
                    );
                  }
                }
              },
              child: const Text('确认导入'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择文件失败：$e')),
      );
    }
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关于简帐'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('版本：v${UpdateService.currentVersionName}'),
            const SizedBox(height: 8),
            const Text('一款完全离线的简帐软件'),
            const SizedBox(height: 8),
            const Text('数据安全：所有数据仅存储在本机，不上传任何服务器'),
            const SizedBox(height: 8),
            const Text('功能：收入记账、支出记账、统计图表、客户管理、税务计算、数据备份、多账本、回收站'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定')),
        ],
      ),
    );
  }
}
