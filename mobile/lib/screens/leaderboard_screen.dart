import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/app_theme.dart';
import '../../providers/data_providers.dart';
import '../../services/data_repository.dart';
import '../../widgets/gamification_cards.dart';
import '../../widgets/state_views.dart';

/// Leaderboard with Students / Faculties scope toggle (spec §14).
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Leaderboard',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: SegmentedButton<LeaderScope>(
              segments: const [
                ButtonSegment(
                  value: LeaderScope.students,
                  label: Text('Students'),
                  icon: Icon(Icons.person_outline, size: 15),
                ),
                ButtonSegment(
                  value: LeaderScope.faculties,
                  label: Text('Faculties'),
                  icon: Icon(Icons.school_outlined, size: 15),
                ),
              ],
              selected: {_scope},
              onSelectionChanged: (s) => setState(() => _scope = s.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? AppColors.green
                      : AppColors.card,
                ),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? Colors.white
                      : AppColors.muted,
                ),
                side: const WidgetStatePropertyAll(
                  BorderSide(color: AppColors.line),
                ),
              ),
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
          final podium = entries.take(3).toList();
          final rest = entries.skip(3).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _Podium(entries: podium),
              const SizedBox(height: 16),
              for (var i = 0; i < rest.length; i++)
                LeaderRow(
                  rank: i + 4,
                  entry: rest[i],
                  isYou: rest[i].id == myId,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  final List<LeaderEntry> entries;
  const _Podium({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final entry in entries)
          Expanded(child: _PodiumCard(entry: entry)),
      ],
    );
  }
}

class _PodiumCard extends StatelessWidget {
  final LeaderEntry entry;
  const _PodiumCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(color: AppColors.line.withValues(alpha: 0.6)),
        ),
        child: Column(
          children: [
            const Icon(Icons.emoji_events, size: 28, color: AppColors.yellow),
            const SizedBox(height: 4),
            Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.foreground,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${entry.points} pts',
              style: const TextStyle(
                fontSize: 13,
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