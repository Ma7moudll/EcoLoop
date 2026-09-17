import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/app_theme.dart';
import '../../providers/data_providers.dart';
import '../../services/data_repository.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/gamification_cards.dart';
import '../../widgets/state_views.dart';

/// Leaderboard with Students / Faculties scope toggle. Redesigned:
/// medal podium (2-1-3), clean rank rows, and a sticky "Your position"
/// card when you are ranked outside the top 3.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  LeaderScope _scope = LeaderScope.students;

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(leaderboardProvider(_scope));
    final myId = ref.watch(currentUserIdProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: AppLogo(size: 22, showWordmark: true),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: _ScopeToggle(
              scope: _scope,
              onChanged: (s) => setState(() => _scope = s),
            ),
          ),
        ),
      ),
      body: entriesAsync.when(
        loading: () => const LoadingView(message: 'Loading rankings…'),
        error: (e, _) => ErrorView(
          message: 'Could not load the leaderboard.',
          onRetry: () => ref.invalidate(leaderboardProvider(_scope)),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return const EmptyView(
              icon: Icons.leaderboard,
              title: 'No rankings yet',
              subtitle: 'Recycle to join the leaderboard.',
            );
          }

          final podiumCount = entries.length >= 3 ? 3 : entries.length;
          final podium = entries.take(podiumCount).toList();
          final rest = entries.skip(podiumCount).toList();

          // Where am I? For the sticky footer card.
          final myIndex = myId == null ? -1 : entries.indexWhere((e) => e.id == myId);

          return RefreshIndicator(
            color: AppColors.green,
            backgroundColor: AppColors.card,
            onRefresh: () async =>
                ref.invalidate(leaderboardProvider(_scope)),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      _Podium(entries: podium, myId: myId),
                      if (rest.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        for (var i = 0; i < rest.length; i++)
                          LeaderRow(
                            rank: i + podiumCount + 1,
                            entry: rest[i],
                            isYou: rest[i].id == myId,
                          ),
                      ],
                    ],
                  ),
                ),
                if (myIndex >= podiumCount)
                  _MyRankCard(
                    rank: myIndex + 1,
                    points: entries[myIndex].points,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scope toggle
// ---------------------------------------------------------------------------

class _ScopeToggle extends StatelessWidget {
  final LeaderScope scope;
  final ValueChanged<LeaderScope> onChanged;

  const _ScopeToggle({required this.scope, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Expanded(child: _pill(LeaderScope.students, 'Students', Icons.person_outline)),
          Expanded(child: _pill(LeaderScope.faculties, 'Faculties', Icons.school_outlined)),
        ],
      ),
    );
  }

  Widget _pill(LeaderScope value, String label, IconData icon) {
    final selected = scope == value;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.green : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 15,
                color: selected ? Colors.white : AppColors.muted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Podium — arranged 2nd / 1st / 3rd with medal colors and initials avatars
// ---------------------------------------------------------------------------

class _Podium extends StatelessWidget {
  final List<LeaderEntry> entries;
  final String? myId;

  const _Podium({required this.entries, required this.myId});

  @override
  Widget build(BuildContext context) {
    // entries are already sorted best-first by the API. Tag each with its
    // rank, then display 2nd | 1st | 3rd (winner tallest, in the middle).
    final ranked = <_RankedEntry>[
      for (var i = 0; i < entries.length; i++)
        _RankedEntry(entries[i], i + 1),
    ];
    final List<_RankedEntry> display;
    if (ranked.length == 1) {
      display = [ranked[0]];
    } else if (ranked.length == 2) {
      display = [ranked[1], ranked[0]];
    } else {
      display = [ranked[1], ranked[0], ranked[2]];
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final r in display)
          Expanded(
            child: _PodiumCard(
              entry: r.entry,
              rank: r.rank,
              isYou: r.entry.id == myId,
              height: _heightForRank(r.rank),
            ),
          ),
      ],
    );
  }

  static double _heightForRank(int rank) => switch (rank) {
        1 => 142.0,
        2 => 120.0,
        _ => 108.0,
      };
}

class _RankedEntry {
  final LeaderEntry entry;
  final int rank;
  const _RankedEntry(this.entry, this.rank);
}

class _PodiumCard extends StatelessWidget {
  final LeaderEntry entry;
  final int rank;
  final bool isYou;
  final double height;

  const _PodiumCard({
    required this.entry,
    required this.rank,
    required this.isYou,
    required this.height,
  });

  static const _medalColors = {
    1: Color(0xFFF4AD17), // gold
    2: Color(0xFF9AA3A0), // silver
    3: Color(0xFFE8590C), // bronze
  };

  String get _initials => entry.name
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0])
      .take(2)
      .join()
      .toUpperCase();

  @override
  Widget build(BuildContext context) {
    final medal = _medalColors[rank]!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 26),
              padding: EdgeInsets.only(top: rank == 1 ? 32 : 28, left: 6, right: 6, bottom: 10),
              width: double.infinity,
              height: height - 26,
              decoration: BoxDecoration(
                color: isYou ? AppColors.mint : AppColors.card,
                borderRadius: BorderRadius.circular(AppRadii.medium),
                border: Border.all(
                  color: isYou ? AppColors.green : AppColors.line.withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: rank == 1 ? 12.5 : 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.foreground,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: medal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${entry.points} pts',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: medal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Avatar circle overlapping the card top; #1 wears a crown badge.
            Positioned(
              top: 0,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: rank == 1 ? 56 : 48,
                    height: rank == 1 ? 56 : 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.card,
                      border: Border.all(color: medal, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        _initials.isEmpty ? '?' : _initials,
                        style: TextStyle(
                          fontSize: rank == 1 ? 17 : 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.deepGreen,
                        ),
                      ),
                    ),
                  ),
                  if (rank == 1)
                    Positioned(
                      top: -8,
                      right: -6,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: AppColors.card,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.workspace_premium,
                            size: 16, color: Color(0xFFF4AD17)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sticky "Your position" card
// ---------------------------------------------------------------------------

class _MyRankCard extends StatelessWidget {
  final int rank;
  final int points;

  const _MyRankCard({required this.rank, required this.points});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.mint,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(color: AppColors.green.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.green,
                shape: BoxShape.circle,
              ),
              child: Text(
                '#$rank',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Your position',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.foreground,
                ),
              ),
            ),
            Text(
              '$points pts',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: AppColors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
