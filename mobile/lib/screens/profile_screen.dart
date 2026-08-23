import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../providers/data_providers.dart';
import '../../providers/providers.dart';
import '../../providers/session_provider.dart';
import '../../providers/shell_tab_provider.dart';
import '../../services/avatar_picker.dart';
import 'challenges_screen.dart';
import 'history_screen.dart';
import 'rewards_screen.dart';
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
              userId: user?.id ?? '',
              name: user?.name ?? 'Student',
              faculty: user?.facultyName ?? '',
              code: user?.studentCode ?? '',
              avatarVersion: user?.avatarVersion ?? 0,
            ),
            data: (me) => _ProfileHeader(
              userId: me?.id ?? user?.id ?? '',
              name: me?.name ?? user?.name ?? 'Student',
              faculty: me?.facultyName ?? user?.facultyName ?? '',
              code: me?.studentCode ?? user?.studentCode ?? '',
              avatarVersion: (me?.avatarVersion ?? user?.avatarVersion ?? 0),
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
                  _PointsStat(label: 'CO₂', value: _co2(ref)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _MenuLink(
            icon: Icons.card_giftcard_outlined,
            title: 'Rewards',
            subtitle: 'Redeem points for real rewards',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const RewardsScreen()),
            ),
          ),
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
            onTap: () => ref.read(shellTabProvider.notifier).select(3),
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

  String _co2(WidgetRef ref) {
    final impact = ref.read(impactProvider).valueOrNull;
    return impact == null ? '—' : '${impact.co2SavedKg.toStringAsFixed(1)} kg';
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

class _ProfileHeader extends ConsumerStatefulWidget {
  final String userId;
  final String name;
  final String faculty;
  final String code;
  final int avatarVersion;

  const _ProfileHeader({
    required this.userId,
    required this.name,
    required this.faculty,
    required this.code,
    required this.avatarVersion,
  });

  @override
  ConsumerState<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends ConsumerState<_ProfileHeader> {
  static Uint8List? _cachedBytes;
  static int _cachedVersion = -1;
  bool _uploading = false;

  Future<Uint8List?> _loadAvatar() async {
    if (widget.avatarVersion <= 0) return null;
    if (_cachedVersion == widget.avatarVersion && _cachedBytes != null) {
      return _cachedBytes;
    }
    final repo = ref.read(authRepositoryProvider);
    final bytes = await repo.fetchAvatarBytes(widget.userId,
        version: widget.avatarVersion);
    _cachedBytes = bytes;
    _cachedVersion = widget.avatarVersion;
    return bytes;
  }

  Future<void> _changePhoto() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (widget.avatarVersion > 0)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      if (picked == 'gallery') {
        final path = await pickImageFromGallery();
        if (path == null) return;
        await ref.read(sessionProvider.notifier).uploadAvatar(path);
      } else {
        await ref.read(sessionProvider.notifier).removeAvatar();
      }
    } on ApiException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not update your photo. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initials = widget.name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join()
        .toUpperCase();
    return Row(
      children: [
        GestureDetector(
          onTap: _uploading ? null : _changePhoto,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  width: 62,
                  height: 62,
                  child: FutureBuilder<Uint8List?>(
                    future: _loadAvatar(),
                    builder: (ctx, snap) {
                      if (snap.hasData && snap.data != null) {
                        return Image.memory(snap.data!,
                            width: 62, height: 62, fit: BoxFit.cover);
                      }
                      return Container(
                        alignment: Alignment.center,
                        color: AppColors.green,
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: _uploading
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.6))
                      : const Icon(Icons.photo_camera_outlined,
                          size: 13, color: AppColors.green),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.name,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.foreground,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                widget.faculty.isNotEmpty ? widget.faculty : 'Student',
                style:
                    const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              if (widget.code.isNotEmpty)
                Text(widget.code,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.green,
                        fontWeight: FontWeight.w700)),
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