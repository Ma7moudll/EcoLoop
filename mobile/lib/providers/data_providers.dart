import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../services/data_repository.dart';
import 'providers.dart';
import 'session_provider.dart';

/// The id of the authenticated user (or null when signed out). Data providers
/// watch this so they re-resolve when the session changes.
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(sessionProvider).user?.id;
});

/// Invalidated (from deposit success / profile refresh) so the new points and
/// history appear immediately.
final currentUserProvider =
    FutureProvider.autoDispose<AppUser?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  return ref.watch(dataRepositoryProvider).fetchMe();
});

final impactProvider = FutureProvider.autoDispose<Impact?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  return ref.watch(dataRepositoryProvider).fetchImpact();
});

final historyProvider =
    FutureProvider.autoDispose<List<WasteHistoryEvent>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const [];
  return ref.watch(dataRepositoryProvider).fetchHistory();
});

final challengesProvider =
    FutureProvider.autoDispose<List<Challenge>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const [];
  return ref.watch(dataRepositoryProvider).fetchChallenges();
});

final leaderboardProvider =
    FutureProvider.family.autoDispose<List<LeaderEntry>, LeaderScope>(
        (ref, scope) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const [];
  return ref.watch(dataRepositoryProvider).fetchLeaderboard(scope: scope);
});

/// Invalidates everything that depends on a points-changing deposit.
void invalidateData(WidgetRef ref) {
  for (final provider in [
    currentUserProvider,
    impactProvider,
    historyProvider,
    challengesProvider,
    leaderboardProvider,
  ]) {
    ref.invalidate(provider);
  }
}