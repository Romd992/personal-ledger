import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class BottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final VoidCallback onAdd;
  // 是否为中间加号预留缺口：仅首页为 true，其他页面6个图标均匀排列、无空洞
  final bool showNotch;

  const BottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onAdd,
    this.showNotch = true,
  });

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      shape: showNotch ? const CircularNotchedRectangle() : null,
      notchMargin: 8,
      elevation: 8,
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(Icons.home_outlined, Icons.home, '首页', 0),
          _buildNavItem(Icons.arrow_downward_outlined, Icons.arrow_downward, '收入', 1),
          _buildNavItem(Icons.arrow_upward_outlined, Icons.arrow_upward, '支出', 2),
          // 仅首页为中间加号预留位置
          if (showNotch) const SizedBox(width: 48),
          _buildNavItem(Icons.people_outline, Icons.people, '客户', 3),
          _buildNavItem(Icons.receipt_long_outlined, Icons.receipt_long, '税务', 4),
          _buildNavItem(Icons.bar_chart_outlined, Icons.bar_chart, '统计', 5),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData outlineIcon, IconData filledIcon, String label, int index) {
    final isSelected = currentIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? filledIcon : outlineIcon,
                color: isSelected ? AppTheme.primaryGold : AppTheme.textHint,
                size: 24,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? AppTheme.primaryGold : AppTheme.textHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 中间浮动加号按钮
class AddFAB extends StatelessWidget {
  final VoidCallback onPressed;
  const AddFAB({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: onPressed,
      backgroundColor: AppTheme.primaryGold,
      elevation: 4,
      shape: const CircleBorder(),
      child: const Icon(Icons.add, color: Colors.white, size: 30),
    );
  }
}
