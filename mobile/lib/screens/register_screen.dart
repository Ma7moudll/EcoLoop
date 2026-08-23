import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/app_text_field.dart';
import 'login_screen.dart';

/// The university faculties, exactly as the backend defines them. The ids are
/// the stable contract; labels are display-only and the SERVER re-validates.
const kFaculties = <String, String>{
  'ENGINEERING': 'Engineering',
  'PHYSICAL_THERAPY': 'Physical Therapy',
  'ART_DESIGN': 'Art & Design',
};

/// Registration: name, student ID, faculty, email, password (+ confirm).
/// Grouped into three visual sections with a sticky call-to-action; every
/// failure — client validation or server rejection — is always surfaced.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _studentCode = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _facultyId;
  String? _facultyError;

  String? _nameError;
  String? _emailError;
  String? _studentCodeError;
  String? _passwordError;
  String? _confirmError;
  String? _banner;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _studentCode.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _validateAndSubmit() {
    FocusScope.of(context).unfocus();
    final name = _name.text.trim();
    final email = _email.text.trim();
    final studentCode = _studentCode.text.trim().toUpperCase();
    final password = _password.text;
    final confirm = _confirm.text;

    setState(() {
      _nameError = name.isEmpty ? 'Enter your name.' : null;
      _emailError = !_isEmail(email) ? 'Enter a valid email address.' : null;
      _studentCodeError = !_isValidStudentCode(studentCode)
          ? 'Enter your student ID (letters, numbers and dashes).'
          : null;
      _facultyError = _facultyId == null ? 'Select your faculty.' : null;
      _passwordError =
          password.length < 6 ? 'Password must be at least 6 characters.' : null;
      _confirmError = confirm != password ? 'Passwords do not match.' : null;
      _banner = null;
    });
    if (_nameError != null ||
        _emailError != null ||
        _studentCodeError != null ||
        _facultyError != null ||
        _passwordError != null ||
        _confirmError != null) {
      return;
    }
    _submit(name, email, studentCode, _facultyId!, password);
  }

  static bool _isEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);

  static bool _isValidStudentCode(String value) =>
      RegExp(r'^[A-Z0-9-]{3,32}$').hasMatch(value);

  Future<void> _submit(String name, String email, String studentCode,
      String facultyId, String password) async {
    setState(() => _busy = true);
    try {
      // Account creation only — the session state stays unauthenticated.
      await ref.read(sessionProvider.notifier).register(
            name: name,
            email: email,
            facultyId: facultyId,
            password: password,
            studentCode: studentCode,
          );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.large)),
          title: const Text('Account created',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.foreground)),
          content: const Text(
            'Welcome to EcoLoop!\n\n'
            'Your account starts with 0 points — recycle at any campus '
            'station to earn your first ones.\n\n'
            'Please log in to continue.',
            style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.muted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Log in',
                  style:
                      TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
      if (!mounted) return;
      // Explicit navigation to an EMPTY login form. The user must sign in
      // themselves; no auto-submit, no stored credentials, no session.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _banner = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _banner = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int get _passwordStrength {
    final p = _password.text;
    if (p.isEmpty) return -1;
    var score = 0;
    if (p.length >= 6) score++;
    if (p.length >= 10) score++;
    if (RegExp(r'(?=.*[a-z])(?=.*[A-Z\d])').hasMatch(p)) score++;
    return score; // 0 weak, 1 fair, 2 good, 3 strong
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.foreground),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _busy ? null : _validateAndSubmit,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Text('Create account',
                        style: TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Already have an account?',
                    style: Theme.of(context).textTheme.bodySmall),
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
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppLogo(size: 36),
              const SizedBox(height: 18),
              Text(
                'Create your account',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Join EcoLoop and earn points for every bottle you recycle.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
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

              // ---- About you -------------------------------------------
              const _SectionLabel('ABOUT YOU'),
              _SectionCard(children: [
                AppTextField(
                  controller: _name,
                  label: 'Full name',
                  icon: Icons.person_outline,
                  hintText: 'Your name',
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {},
                  errorText: _nameError,
                ),
                const SizedBox(height: 14),
                AppTextField(
                  controller: _studentCode,
                  label: 'Student ID',
                  icon: Icons.badge_outlined,
                  hintText: 'e.g. S-2024-0137',
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {},
                  errorText: _studentCodeError,
                ),
              ]),

              // ---- Faculty ---------------------------------------------
              const _SectionLabel('FACULTY'),
              _SectionCard(children: [
                DropdownButtonFormField<String>(
                  value: _facultyId,
                  decoration: InputDecoration(
                    labelText: 'Select your faculty',
                    prefixIcon: const Icon(Icons.school_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    errorText: _facultyError,
                  ),
                  hint: const Text('Select your faculty'),
                  items: kFaculties.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _facultyId = v;
                    _facultyError = null;
                  }),
                ),
              ]),

              // ---- Sign-in details -------------------------------------
              const _SectionLabel('SIGN-IN DETAILS'),
              _SectionCard(children: [
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
                const SizedBox(height: 14),
                AppTextField(
                  controller: _password,
                  label: 'Password',
                  icon: Icons.lock_outline,
                  obscureText: true,
                  showToggle: true,
                  hintText: '6+ characters',
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  errorText: _passwordError,
                ),
                _PasswordStrength(score: _passwordStrength),
                const SizedBox(height: 10),
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
              ]),
              const SizedBox(height: 8),
              Text(
                'New accounts start with 0 points. You earn points only when '
                'the station confirms a real deposit.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: AppColors.muted,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line.withValues(alpha: 0.7)),
      ),
      child: Column(children: children),
    );
  }
}

class _PasswordStrength extends StatelessWidget {
  final int score; // -1 hidden, 0..3
  const _PasswordStrength({required this.score});

  @override
  Widget build(BuildContext context) {
    if (score < 0) return const SizedBox.shrink();
    const colors = [AppColors.danger, AppColors.orange, AppColors.blue, AppColors.green];
    const labels = ['Weak password', 'Fair password', 'Good password', 'Strong password'];
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                decoration: BoxDecoration(
                  color: i < score ? colors[score] : AppColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          const SizedBox(width: 10),
          Text(
            labels[score],
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: colors[score],
            ),
          ),
        ],
      ),
    );
  }
}
