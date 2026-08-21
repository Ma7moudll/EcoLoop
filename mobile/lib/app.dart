import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../screens/app_shell.dart';
import '../../screens/error_screen.dart';
import '../../screens/login_screen.dart';
import '../../screens/splash_screen.dart';
import '../../widgets/app_logo.dart';

/// Recycle Vision app root. Session status drives which surface is shown:
/// splash → (login | register) → shell.
class RecycleVisionApp extends StatelessWidget {
  const RecycleVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Recycle Vision',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return switch (session.status) {
      SessionStatus.initial || SessionStatus.loading => const SplashScreen(),
      SessionStatus.error =>
        ErrorScreen(
          message: session.error ?? 'Unable to connect.',
          onRetry: () => ref.read(sessionProvider.notifier).bootstrap(),
        ),
      SessionStatus.anonymous => const LoginScreen(),
      SessionStatus.ready => const AppShell(),
    };
  }
}

/// Small understated logo used by error surfaces.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppLogo(size: 26);
  }
}