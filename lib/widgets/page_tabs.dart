import 'package:flutter/material.dart';

/// TikTok-style text-only tab bar for switching between 下载 and 刷视频.
class PageTabs extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabChanged;

  const PageTabs({
    super.key,
    required this.currentIndex,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TabLabel(
          label: '下载',
          selected: currentIndex == 0,
          onTap: () => onTabChanged(0),
        ),
        const SizedBox(width: 24),
        _TabLabel(
          label: '刷视频',
          selected: currentIndex == 1,
          onTap: () => onTabChanged(1),
        ),
      ],
    );
  }
}

class _TabLabel extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabLabel({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.blue : Colors.white54,
            fontSize: 15,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
