import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_theme.dart';
import 'providers/session_provider.dart';
import 'screens/app_shell.dart';
import 'screens/error_screen.dart';
import 'screens/login_screen.dart';

/// EcoLoop app root. No splash screen: the login UI paints immediately while
/// the stored session is validated in the background. A restored session is
/// NEVER entered silently — the login screen shows an explicit
/// "Continue as …" card that the user must tap.
class RecycleVisionApp extends ConsumerStatefulWidget {
  const RecycleVisionApp({super.key});

  @override
  ConsumerState<RecycleVisionApp> createState() => _RecycleVisionAppState();
}

class _RecycleVisionAppState extends ConsumerState<RecycleVisionApp> {
  @override
  void initState() {
    super.initState();
    // Fire-and-forget session restore — never blocks first paint.
    Future<void>.microtask(
        () => ref.read(sessionProvider.notifier).bootstrap());
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final enterShell =
        session.status == SessionStatus.ready && !session.autoRestored;
    return MaterialApp(
      title: 'EcoLoop',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: session.status == SessionStatus.error && !enterShell
          ? ErrorScreen(
              message: session.error ?? 'Unable to connect.',
              onRetry: () => ref.read(sessionProvider.notifier).bootstrap(),
            )
          : enterShell
              ? const AppShell()
              : const LoginScreen(),
    );
  }
}
