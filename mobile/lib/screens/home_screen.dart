import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../providers/data_providers.dart';
import '../../providers/session_provider.dart';
import '../../services/data_repository.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/gamification_cards.dart';
import '../../widgets/history_row.dart';
import '../../widgets/state_views.dart';
import 'challenges_screen.dart';
import 'history_screen.dart';
import 'recycle/recycle_screen.dart';
import 'settings_screen.dart';

/// Home: live user row, points hero, recent activity, challenges preview.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.user;
    final pointsAsync = ref.watch(currentUserProvider);
    final historyAsync = ref.watch(historyProvider);
    final challengesAsync = ref.watch(challengesProvider);
    final impactAsync = ref.watch(impactProvider);
    final facultyAsync =
        ref.watch(leaderboardProvider(LeaderScope.faculties));

    final firstName =
        (user?.name.isNotEmpty ?? false) ? user!.name.split(' ').first : 'there';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        toolbarHeight: 58,
        titleSpacing: 0,
        title: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: AppLogo(size: 22, showWordmark: true),
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(currentUserProvider);
          ref.invalidate(historyProvider);
          ref.invalidate(challengesProvider);
          // Give providers a moment; UI updates automatically.
          await Future<void>.delayed(const Duration(milliseconds: 300));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(
              '${greetingFor(DateTime.now())}, $firstName!',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            if (user != null)
              Text(
                user.facultyName,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            const SizedBox(height: 16),
            // Points card
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: pointsAsync.when(
                loading: () => const _CardSkeleton(height: 130),
                error: (e, _) => PointsCard(points: user?.points ?? 0),
                data: (me) => PointsCard(points: me?.points ?? user?.points ?? 0),
              ),
            ),
            // Impact strip + faculty rank (live from the backend)
            _ImpactAndRank(
              impactAsync: impactAsync,
              facultyAsync: facultyAsync,
              facultyId: user?.facultyId,
              facultyName: user?.facultyName,
            ),
            const SizedBox(height: 16),
            // Recycle CTA — station-camera flow (phone identifies the station,
            // the station camera classifies the item).
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const RecycleScreen()),
              ),
              borderRadius: BorderRadius.circular(AppRadii.card),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.green, Color(0xFF0C7A69)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(AppRadii.card),
                  ),
                child: const Row(
                  children: [
                    Icon(Icons.recycling, color: Colors.white, size: 32),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recycle now',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Go to an EcoLoop station and scan its QR. The '
                            'station camera routes your item and you earn '
                            'points.',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _SectionTitle('Recent activity'),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const HistoryScreen()),
                  ),
                  child: const Text('See all'),
                ),
              ],
            ),
            historyAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: LoadingView(),
              ),
              error: (e, _) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: EmptyView(
                  icon: Icons.history,
                  title: 'No activity yet',
                  subtitle: 'Your recycled items will appear here.',
                ),
              ),
              data: (items) => items.isEmpty
                  ? const EmptyView(
                      icon: Icons.history,
                      title: 'No activity yet',
                      subtitle:
                          'Scan your first item and start earning points.',
                    )
                  : Column(
                      children: [
                        for (final item in items.take(3))
                          HistoryRow(event: item),
                      ],
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _SectionTitle('Active challenges'),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const ChallengesScreen()),
                  ),
                  child: const Text('View all'),
                ),
              ],
            ),
            challengesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: LoadingView(),
              ),
              error: (e, _) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: EmptyView(
                  icon: Icons.emoji_events_outlined,
                  title: 'Challenges unavailable',
                ),
              ),
              data: (items) => items.isEmpty
                  ? const EmptyView(
                      icon: Icons.emoji_events_outlined,
                      title: 'No challenges right now',
                    )
                  : Column(
                      children: [
                        for (final c in items.where((c) => c.active).take(2))
                          ChallengeCard(challenge: c),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: AppColors.foreground,
      ),
    );
  }
}

/// Home impact summary: recycled kg + CO₂ saved + faculty rank, all computed
/// server-side and shown verbatim.
class _ImpactAndRank extends StatelessWidget {
  final AsyncValue<Impact?> impactAsync;
  final AsyncValue<List<LeaderEntry>> facultyAsync;
  final String? facultyId;
  final String? facultyName;

  const _ImpactAndRank({
    required this.impactAsync,
    required this.facultyAsync,
    required this.facultyId,
    required this.facultyName,
  });

  int? get _myRank {
    final entries = facultyAsync.valueOrNull;
    if (entries == null || entries.isEmpty) return null;
    final match = facultyName != null && facultyName!.isNotEmpty
        ? entries.indexWhere((e) => e.name == facultyName)
        : -1;
    return match >= 0 ? match + 1 : null;
  }

  @override
  Widget build(BuildContext context) {
    final impact = impactAsync.valueOrNull;
    if (impact == null) return const SizedBox.shrink();
    final rank = _myRank;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.line.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  icon: Icons.scale_outlined,
                  accent: AppColors.green,
                  label: 'Recycled',
                  value: Fmt.kilo(impact.recycledKg),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStat(
                  icon: Icons.cloud_outlined,
                  accent: AppColors.blue,
                  label: 'CO₂ saved',
                  value: Fmt.co2(impact.co2SavedKg),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStat(
                  icon: Icons.inventory_2_outlined,
                  accent: AppColors.deepGreen,
                  label: 'Items',
                  value: '${impact.itemsRecycled}',
                ),
              ),
            ],
          ),
          if (rank != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.rewardBg,
                borderRadius: BorderRadius.circular(AppRadii.small),
              ),
              child: Row(
                children: [
                  const Icon(Icons.school_outlined,
                      size: 15, color: AppColors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${facultyName ?? 'Your faculty'} is #$rank on the '
                      'faculty leaderboard',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.deepGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String label;
  final String value;

  const _MiniStat({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: accent),
        const SizedBox(width: 6),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              Text(
                label,
                style:
                    const TextStyle(fontSize: 9, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  final double height;
  const _CardSkeleton({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.line.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      ),
    );
  }
}