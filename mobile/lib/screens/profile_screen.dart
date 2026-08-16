import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../providers/data_providers.dart';
import '../../providers/session_provider.dart';
import '../../providers/shell_tab_provider.dart';
import 'challenges_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

/// Profile: identity from the backend, quick links, and an explicit log out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.user;
    final meAsync = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.w800),
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          meAsync.when(
            loading: () => const _ProfileSkeleton(),
            error: (e, st) => _ProfileHeader(
              name: user?.name ?? 'Student',
              faculty: user?.facultyName ?? '',
              code: user?.studentCode ?? '',
            ),
            data: (me) => _ProfileHeader(
              name: me?.name ?? user?.name ?? 'Student',
              faculty: me?.facultyName ?? user?.facultyName ?? '',
              code: me?.studentCode ?? user?.studentCode ?? '',
            ),
          ),
          const SizedBox(height: 16),
          // Points strip
          meAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (e, st) => const SizedBox.shrink(),
            data: (me) => Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.rewardBg,
                borderRadius: BorderRadius.circular(AppRadii.medium),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _PointsStat(label: 'Points', value: '${me?.points ?? 0}'),
                  _PointsStat(label: 'Recycled', value: _kg(ref)),
                  _PointsStat(label: 'Items', value: _items(ref)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _MenuLink(
            icon: Icons.recycling_outlined,
            title: 'Recycling history',
            subtitle: 'View every deposit',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const HistoryScreen()),
            ),
          ),
          _MenuLink(
            icon: Icons.emoji_events_outlined,
            title: 'Challenges',
            subtitle: 'Active challenges and rewards',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ChallengesScreen()),
            ),
          ),
          _MenuLink(
            icon: Icons.leaderboard_outlined,
            title: 'Leaderboard',
            subtitle: 'Compare with your faculty',
            onTap: () => ref.read(shellTabProvider.notifier).select(2),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => ref.read(sessionProvider.notifier).logout(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
            ),
            icon: const Icon(Icons.logout, size: 17),
            label: const Text('Log out'),
          ),
        ],
      ),
    );
  }

  String _kg(WidgetRef ref) {
    final impact = ref.read(impactProvider).valueOrNull;
    return impact == null ? '—' : '${impact.recycledKg.toStringAsFixed(1)} kg';
  }

  String _items(WidgetRef ref) {
    final impact = ref.read(impactProvider).valueOrNull;
    return '${impact?.itemsRecycled ?? 0}';
  }
}

class _PointsStat extends StatelessWidget {
  final String label;
  final String value;
  const _PointsStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.deepGreen,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final String name;
  final String faculty;
  final String code;

  const _ProfileHeader({required this.name, required this.faculty, required this.code});

  @override
  Widget build(BuildContext context) {
    final initials = name.split(' ').where((w) => w.isNotEmpty).map((w) => w[0]).take(2).join().toUpperCase();
    return Row(
      children: [
        Container(
          width: 62,
          height: 62,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.green,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            initials,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.foreground,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                faculty.isNotEmpty ? faculty : 'Student',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              if (code.isNotEmpty)
                Text(code, style: const TextStyle(fontSize: 11, color: AppColors.green, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }
}

class _MenuLink extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuLink({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.medium),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(color: AppColors.line.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.mint,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 18, color: AppColors.green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.foreground,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(18)),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 120, height: 16, color: AppColors.line, margin: const EdgeInsets.only(bottom: 8)),
            Container(width: 80, height: 12, color: AppColors.line),
          ],
        ),
      ],
    );
  }
}