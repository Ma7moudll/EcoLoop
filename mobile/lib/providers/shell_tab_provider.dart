import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which shell tab is active (page index into the 5-tab IndexedStack:
/// Home=0, Impact=1, Rewards=2, Leaderboard=3, Profile=4). Kept in a provider
/// so pushed flows can request a specific tab, e.g. "View my impact" →
/// Impact. Scanning is the floating action button, not a tab.
final shellTabProvider =
    NotifierProvider<ShellTabNotifier, int>(ShellTabNotifier.new);

class ShellTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) {
    if (index >= 0 && index <= 4) {
      state = index;
    }
  }
}