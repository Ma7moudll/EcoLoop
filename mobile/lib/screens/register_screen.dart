import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/app_text_field.dart';

/// Registration: name, email, password (+ confirm). Minimal but real — the
/// account is created on the backend and the session starts immediately.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _banner;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _validateAndSubmit() {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    final confirm = _confirm.text;

    setState(() {
      _nameError = name.isEmpty ? 'Enter your name.' : null;
      _emailError = !_isEmail(email) ? 'Enter a valid email address.' : null;
      _passwordError = password.length < 6
          ? 'Password must be at least 6 characters.'
          : null;
      _confirmError =
          confirm != password ? 'Passwords do not match.' : null;
      _banner = null;
    });
    if (_nameError != null ||
        _emailError != null ||
        _passwordError != null ||
        _confirmError != null) {
      return;
    }
    _submit(name, email, password);
  }

  static bool _isEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);

  Future<void> _submit(String name, String email, String password) async {
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).register(
            name: name,
            email: email,
            password: password,
          );
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create account'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppLogo(size: 34),
              const SizedBox(height: 20),
              Text(
                'Join and start earning points',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Your impact is rewarded — every recycled item counts.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 22),
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
                controller: _name,
                label: 'Full name',
                icon: Icons.person_outline,
                hintText: 'Your name',
                textInputAction: TextInputAction.next,
                onChanged: (_) {},
                errorText: _nameError,
              ),
              const SizedBox(height: 16),
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
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _password,
                label: 'Password',
                icon: Icons.lock_outline,
                obscureText: true,
                showToggle: true,
                hintText: '6+ characters',
                textInputAction: TextInputAction.next,
                onChanged: (_) {},
                errorText: _passwordError,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _confirm,
                label: 'Confirm password',
                icon: Icons.lock_outline,
                obscureText: true,
                showToggle: true,
                textInputAction: TextInputAction.done,
                onChanged: (_) {},
                errorText: _confirmError,
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
                    : const Text('Create account'),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Already have an account?',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  TextButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Log in'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}