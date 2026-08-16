import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../providers/data_providers.dart';
import '../../widgets/gamification_cards.dart';
import '../../widgets/state_views.dart';

/// All active + completed challenges (spec §18).
class ChallengesScreen extends ConsumerWidget {
  const ChallengesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challengesAsync = ref.watch(challengesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Challenges',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: challengesAsync.when(
        loading: () => const LoadingView(message: 'Loading challenges…'),
        error: (e, _) => ErrorView(
          message: 'Could not load challenges.',
          onRetry: () => ref.invalidate(challengesProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(
              icon: Icons.emoji_events_outlined,
              title: 'No challenges right now',
              subtitle: 'Check back after your next deposit.',
            );
          }
          final active = items.where((c) => c.active).toList();
          final completed = items.where((c) => c.completed).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (active.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No active challenges. Keep recycling!',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.muted),
                  ),
                )
              else
                for (final c in active) ChallengeCard(challenge: c),
              if (completed.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  'Completed',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.foreground,
                  ),
                ),
                const SizedBox(height: 8),
                for (final c in completed) ChallengeCard(challenge: c),
              ],
            ],
          );
        },
      ),
    );
  }
}