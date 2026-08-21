import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/shell_tab_provider.dart';
import '../../widgets/app_bottom_nav.dart';
import 'home_screen.dart';
import 'impact_screen.dart';
import 'leaderboard_screen.dart';
import 'profile_screen.dart';
import 'recycle/recycle_screen.dart';

/// Authenticated shell: four real tabs (Home / Impact / Leaderboard / Profile)
/// plus the emphasized center Recycle action, which pushes the full-screen
/// station-camera recycle flow rather than swapping a tab.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static final _pages = <Widget>[
    const HomeScreen(),
    const ImpactScreen(),
    const LeaderboardScreen(),
    const ProfileScreen(),
  ];

  void _onNavSelected(BuildContext context, WidgetRef ref, int navIndex) {
    // The nav bar has 5 slots; slot 2 is the emphasized Recycle action, which
    // is a full-screen flow rather than a tab.
    if (navIndex == 2) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const RecycleScreen()),
      );
      return;
    }
    // Map nav slot → page index (Home, Impact, Leaderboard, Profile).
    final pageIndex = navIndex > 2 ? navIndex - 1 : navIndex;
    ref.read(shellTabProvider.notifier).select(pageIndex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageIndex = ref.watch(shellTabProvider);
    // Show the highlighted nav slot that matches the active page.
    final navIndex = pageIndex >= 2 ? pageIndex + 1 : pageIndex;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: pageIndex, children: _pages),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: AppBottomNav(
          currentIndex: navIndex,
          onSelected: (nav) => _onNavSelected(context, ref, nav),
        ),
      ),
    );
  }
}