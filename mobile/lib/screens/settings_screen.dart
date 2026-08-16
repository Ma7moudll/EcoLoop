import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_config.dart';
import '../../core/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../widgets/app_logo.dart';

/// Settings: runtime configuration read-out, session management, about. No
/// writable settings are persisted client-side in the MVP (constants are
/// compile-time / backend-driven), so this screen is informational + actions.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _Group(
            title: 'App',
            children: [
              _SwitchTile(
                icon: Icons.science_outlined,
                title: 'Demo mode',
                subtitle: 'Simulated AI + station responses from the backend.',
                value: AppConfig.demoMode,
                onChanged: (_) {}, // read-only in MVP
              ),
              _InfoTile(
                icon: Icons.dns_outlined,
                title: 'API server',
                subtitle: AppConfig.apiBaseUrl,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Group(
            title: 'Account',
            children: [
              _InfoTile(
                icon: Icons.badge_outlined,
                title: 'Signed in as',
                subtitle: user?.name ?? 'Not signed in',
              ),
              if (user != null)
                _InfoTile(
                  icon: Icons.alternate_email,
                  title: 'Student code',
                  subtitle: user.studentCode,
                ),
            ],
          ),
          const SizedBox(height: 18),
          _Group(
            title: 'About',
            children: [
              const _InfoTile(
                icon: Icons.info_outline,
                title: 'Version',
                subtitle: 'Recycle Vision MVP 1.0',
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 10, 4, 0),
                child: Row(
                  children: [
                    AppLogo(size: 20, showWordmark: true),
                    Spacer(),
                    Text(
                      'Recycle. Score. Reward.',
                      style: TextStyle(fontSize: 10, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
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
}

class _Group extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Group({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w800,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            border: Border.all(color: AppColors.line.withValues(alpha: 0.6)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}