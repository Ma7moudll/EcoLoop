import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Bottom navigation bar with five destinations:
/// Home, Impact, Rewards, Leaderboard, Profile.
/// Scanning lives on the floating action button outside this bar.
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelected;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.foreground,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Semantics(
        container: true,
        label: 'Main navigation',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                index: 0,
                icon: Icons.home_rounded,
                label: 'Home',
                selected: currentIndex == 0,
                onTap: () => onSelected(0),
              ),
              _NavItem(
                index: 1,
                icon: Icons.eco_rounded,
                label: 'Impact',
                selected: currentIndex == 1,
                onTap: () => onSelected(1),
              ),
              _NavItem(
                index: 2,
                icon: Icons.card_giftcard_rounded,
                label: 'Rewards',
                selected: currentIndex == 2,
                onTap: () => onSelected(2),
              ),
              _NavItem(
                index: 3,
                icon: Icons.leaderboard_rounded,
                label: 'Leaderboard',
                selected: currentIndex == 3,
                onTap: () => onSelected(3),
              ),
              _NavItem(
                index: 4,
                icon: Icons.person_rounded,
                label: 'Profile',
                selected: currentIndex == 4,
                onTap: () => onSelected(4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final int index;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.index,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.green : AppColors.muted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? AppColors.green : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
