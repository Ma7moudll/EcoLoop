import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/app_text_field.dart';
import 'register_screen.dart';

/// Login with email + password. Errors (invalid credentials, offline) surface
/// in an inline banner.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _emailError;
  String? _passwordError;
  String? _banner;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _validateAndSubmit() {
    final email = _email.text.trim();
    final password = _password.text;
    setState(() {
      _emailError = email.isEmpty ? 'Enter your email address.' : null;
      _passwordError = password.isEmpty ? 'Enter your password.' : null;
      _banner = null;
    });
    if (_emailError != null || _passwordError != null) return;
    _submit(email, password);
  }

  Future<void> _submit(String email, String password) async {
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).login(email, password);
      // Navigation relies on app.dart swapping home to the shell once the
      // session is ready. If this screen was PUSHED above it (e.g. after
      // registration), pop so the authenticated home is revealed.
      if (!mounted) return;
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _banner = e.message);
    } catch (_) {
      setState(() => _banner = 'Unexpected error. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final restored = session.status == SessionStatus.ready &&
        session.autoRestored &&
        session.user != null;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppLogo(size: 40),
              const SizedBox(height: 30),
              if (restored) ...[
                _RestoredSessionCard(
                  name: session.user!.name,
                  subtitle: session.user!.studentCode,
                  onContinue: () =>
                      ref.read(sessionProvider.notifier).continueRestored(),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    const Expanded(child: Divider(color: AppColors.line)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'or sign in with another account',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const Expanded(child: Divider(color: AppColors.line)),
                  ],
                ),
                const SizedBox(height: 22),
              ],
              Text(
                'Welcome back!',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Log in to continue recycling.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 26),
              if (_banner != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.errorBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          size: 17, color: AppColors.danger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _banner!,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              AppTextField(
                controller: _email,
                label: 'Email address',
                icon: Icons.mail_outline,
                hintText: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
                autofillHints: true,
                autofillHintsGroup: 'email',
                textInputAction: TextInputAction.next,
                onChanged: (_) {},
                errorText: _emailError,
                onSubmitted: () => _passwordFocus(context),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _password,
                label: 'Password',
                icon: Icons.lock_outline,
                obscureText: true,
                showToggle: true,
                textInputAction: TextInputAction.done,
                onChanged: (_) {},
                errorText: _passwordError,
                onSubmitted: () => _validateAndSubmit(),
              ),
              const SizedBox(height: 26),
              ElevatedButton(
                onPressed: _busy ? null : _validateAndSubmit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Text('Log in'),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'New to EcoLoop?',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) => const RegisterScreen()),
                            ),
                    child: const Text('Create account'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _passwordFocus(BuildContext context) {
    FocusScope.of(context).nextFocus();
  }
}

/// One-tap entry for a validated stored session. Nothing happens until the
/// user taps Continue — the app never silently opens an account.
class _RestoredSessionCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final VoidCallback onContinue;

  const _RestoredSessionCard({
    required this.name,
    required this.subtitle,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final initials = name.split(' ').where((w) => w.isNotEmpty).map((w) => w[0]).take(2).join().toUpperCase();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.mint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.green,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initials.isEmpty ? '?' : initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back,',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: onContinue,
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }
}