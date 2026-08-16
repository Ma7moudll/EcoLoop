import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which shell tab is active (page index into the 4-tab IndexedStack:
/// Home=0, Impact=1, Leaderboard=2, Profile=3). Kept in a provider so the scan
/// flow (pushed on top of the shell) can request a specific tab, e.g. "View my
/// impact" → Impact.
final shellTabProvider =
    NotifierProvider<ShellTabNotifier, int>(ShellTabNotifier.new);

class ShellTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) {
    if (index >= 0 && index <= 3) {
      state = index;
    }
  }
}