import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/app_text_field.dart';
import 'register_screen.dart';

/// Login with email + password. Errors (invalid credentials, offline) surface
/// in an inline banner; a demo account shortcut is provided because the seeded
/// server account is part of demo mode, never a private user.
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
    } on ApiException catch (e) {
      setState(() => _banner = e.message);
    } catch (_) {
      setState(() => _banner = 'Unexpected error. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _demoLogin() async {
    setState(() {
      _busy = true;
      _banner = null;
      _email.text = 'demo@recycle.vision';
      _password.text = 'demo123';
    });
    await _submit('demo@recycle.vision', 'demo123');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppLogo(size: 40),
              const SizedBox(height: 30),
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
                    'New to Recycle Vision?',
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
              const SizedBox(height: 6),
              const Divider(height: 20),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _busy ? null : _demoLogin,
                    icon: const Icon(Icons.auto_awesome, size: 15),
                    label: const Text('Try the demo account'),
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