import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../screens/register_screen.dart' show kFaculties;
import '../../widgets/app_logo.dart';

/// Settings: account management (edit profile, change password), support,
/// about and session control. No infrastructure details are exposed here.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
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
              if (user != null) ...[
                _ActionTile(
                  icon: Icons.person_outline,
                  title: 'Edit profile',
                  onTap: () => _editProfile(),
                ),
                _ActionTile(
                  icon: Icons.lock_outline,
                  title: 'Change password',
                  onTap: () => _changePassword(),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          _Group(
            title: 'Support',
            children: [
              _ActionTile(
                icon: Icons.help_outline,
                title: 'Help & FAQ',
                onTap: () => _showInfo(
                  'Help & FAQ',
                  'Scan a recyclable item at any smart station to earn '
                      'points. Medium-confidence results ask you to confirm; '
                      'low confidence asks you to retake the photo.',
                ),
              ),
              _ActionTile(
                icon: Icons.mail_outline,
                title: 'Contact support',
                subtitle: 'support@ecoloop.example.edu',
                onTap: () => _showInfo(
                  'Contact support',
                  'Email support@ecoloop.example.edu with your student code '
                      'and a short description of the issue.',
                ),
              ),
              _ActionTile(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy',
                onTap: () => _showInfo(
                  'Privacy',
                  'EcoLoop stores only your name, university email, faculty '
                      'and recycling activity. Photos are used solely for '
                      'waste classification.',
                ),
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

  Future<void> _editProfile() async {
    final user = ref.read(sessionProvider).user;
    if (user == null) return;
    String name = user.name;
    String? facultyId = user.facultyId;
    String? error;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Edit profile',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              TextField(
                controller: TextEditingController(text: name)
                  ..selection = TextSelection.collapsed(offset: name.length),
                decoration: InputDecoration(
                  labelText: 'Display name',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  errorText: error,
                ),
                onChanged: (v) => name = v,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: kFaculties.containsKey(facultyId) ? facultyId : null,
                decoration: InputDecoration(
                  labelText: 'Faculty',
                  prefixIcon: const Icon(Icons.school_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                items: kFaculties.entries
                    .map((e) => DropdownMenuItem(
                        value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setSheet(() => facultyId = v),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () async {
                  final trimmed = name.trim();
                  if (trimmed.isEmpty) {
                    setSheet(() => error = 'Name cannot be empty.');
                    return;
                  }
                  final navigator = Navigator.of(ctx);
                  final ok = await ref
                      .read(sessionProvider.notifier)
                      .updateProfile(
                          name: trimmed == user.name ? null : trimmed,
                          facultyId: facultyId == user.facultyId
                              ? null
                              : facultyId)
                      .then((_) => true)
                      .catchError((_) => false);
                  navigator.pop(ok);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(saved == true
          ? 'Profile updated.'
          : 'Could not update profile. Try again.'),
    ));
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    String? error;
    bool busy = false;

    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Change password',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('You will be signed out and must log in again.',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 16),
              TextField(
                controller: current,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Current password',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: next,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'New password (8+ characters)',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirm,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Confirm new password',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  errorText: error,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (next.text.length < 8) {
                          setSheet(() =>
                              error = 'New password must be 8+ characters.');
                          return;
                        }
                        if (next.text != confirm.text) {
                          setSheet(() => error = 'Passwords do not match.');
                          return;
                        }
                        setSheet(() {
                          busy = true;
                          error = null;
                        });
                        final navigator = Navigator.of(ctx);
                        try {
                          await ref
                              .read(sessionProvider.notifier)
                              .changePassword(
                                currentPassword: current.text,
                                newPassword: next.text,
                              );
                          navigator.pop(true);
                        } catch (_) {
                          setSheet(() {
                            busy = false;
                            error =
                                'Change failed — check your current password.';
                          });
                        }
                      },
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Change password'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    // changePassword signs the session out on success → app shows login.
  }

  void _showInfo(String title, String body) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body, style: const TextStyle(fontSize: 13.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
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
    this.subtitle = '',
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
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: const TextStyle(
                        fontSize: 10.5, color: AppColors.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.green),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                ),
              ),
            ),
            if (subtitle != null)
              Flexible(
                child: Text(
                  subtitle!,
                  style:
                      const TextStyle(fontSize: 10.5, color: AppColors.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
