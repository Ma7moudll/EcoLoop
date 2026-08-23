import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../providers/shell_tab_provider.dart';
import '../../widgets/app_bottom_nav.dart';
import 'home_screen.dart';
import 'impact_screen.dart';
import 'leaderboard_screen.dart';
import 'profile_screen.dart';
import 'recycle/recycle_screen.dart';
import 'rewards_screen.dart';

/// Authenticated shell: five tabs (Home / Impact / Rewards / Leaderboard /
/// Profile) plus the floating Scan action button, which pushes the full-screen
/// station-camera recycle flow rather than swapping a tab.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static final _pages = <Widget>[
    const HomeScreen(),
    const ImpactScreen(),
    const RewardsScreen(),
    const LeaderboardScreen(),
    const ProfileScreen(),
  ];

  void _openScanner(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const RecycleScreen()),
    );
  }

  void _onNavSelected(BuildContext context, WidgetRef ref, int navIndex) {
    // Nav slots map 1:1 onto pages: Home=0, Impact=1, Rewards=2,
    // Leaderboard=3, Profile=4. Scanning is the FAB, not a tab.
    ref.read(shellTabProvider.notifier).select(navIndex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageIndex = ref.watch(shellTabProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: pageIndex, children: _pages),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'scan-fab',
        onPressed: () => _openScanner(context),
        backgroundColor: AppColors.green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.recycling, size: 22),
        label: const Text('Scan',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: AppBottomNav(
          currentIndex: pageIndex,
          onSelected: (nav) => _onNavSelected(context, ref, nav),
        ),
      ),
    );
  }
}