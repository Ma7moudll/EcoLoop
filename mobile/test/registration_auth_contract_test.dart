import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recycle_vision/app.dart';
import 'package:recycle_vision/core/api_client.dart';
import 'package:recycle_vision/providers/providers.dart';
import 'package:recycle_vision/providers/session_provider.dart';
import 'package:recycle_vision/screens/app_shell.dart';
import 'package:recycle_vision/screens/login_screen.dart';
import 'package:recycle_vision/screens/register_screen.dart';
import 'package:recycle_vision/services/auth_repository.dart';
import 'package:shared/shared.dart';

import 'helpers.dart';

/// Records every secure-storage mutation so tests can prove NO token is
/// persisted by registration.
class SpyStorage implements FlutterSecureStorage {
  final Map<String, String> values = {};
  final List<String> writes = [];
  final List<String> deletes = [];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) return;
    writes.add(key);
    values[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      values[key];

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deletes.add(key);
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Auth double that records which session-establishing calls happen and
/// routes token persistence through the [SpyStorage].
class SpyAuthRepository extends AuthRepository {
  SpyAuthRepository(this.storage, {this.hasStoredSession = false})
      : super(ApiClient('http://localhost:9'), storage);

  final SpyStorage storage;
  final bool hasStoredSession;

  int registerCalls = 0;
  int loginCalls = 0;
  List<String> get registeredEmails => _registeredEmails;
  final List<String> _registeredEmails = [];

  @override
  Future<String?> restoreToken() async =>
      hasStoredSession ? (storage.values['ecoloop_session'] ?? 'stored-jwt') : null;

  @override
  Future<void> persistToken(String token) async {
    await storage.write(key: 'ecoloop_session', value: token);
  }

  @override
  Future<void> clearSession() async {
    // Local wipe only in tests — the real one also POSTs /auth/logout.
    await storage.delete(key: 'ecoloop_session');
  }

  @override
  Future<AppUser> register({
    required String name,
    required String email,
    required String facultyId,
    required String password,
    required String studentCode,
  }) async {
    registerCalls++;
    _registeredEmails.add(email);
    // Mirror the production repository: any pre-existing stored session is
    // revoked and wiped BEFORE account creation.
    await clearSession();
    // Server contract: creation response carries the new user, never a token.
    return fakeUser(points: 0);
  }

  @override
  Future<(String, AppUser)> login(String email, String password) async {
    loginCalls++;
    // Mirror the production repository: only LOGIN persists a token.
    await persistToken('fresh-login-jwt');
    return ('fresh-login-jwt', fakeUser(points: 45));
  }

  @override
  Future<AppUser> fetchMe() async => fakeUser(points: 0);
}

Future<void> _fillRegisterForm(WidgetTester tester) async {
  await tester.enterText(find.byKey(const ValueKey('Full name')), 'Test User');
  await tester.enterText(
      find.byKey(const ValueKey('Student ID')), 'S-REG-0001');
  await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Engineering').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Engineering').last);
  await tester.pumpAndSettle();
  await tester.enterText(
      find.byKey(const ValueKey('Email address')), 'reg.test@uni.edu');
  await tester.enterText(
      find.byKey(const ValueKey('Password')), 'secret99');
  await tester.enterText(
      find.byKey(const ValueKey('Confirm password')), 'secret99');
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Create account'));
  await tester.pumpAndSettle();
}

(ProviderContainer, Widget) _app(AuthRepository repo) {
  final container = ProviderContainer(overrides: [
    authRepositoryProvider.overrideWithValue(repo),
    dataRepositoryProvider.overrideWithValue(FakeDataRepository()),
  ]);
  return (
    container,
    UncontrolledProviderScope(
      container: container,
      child: const RecycleVisionApp(),
    ),
  );
}

void main() {
  testWidgets('registration_does_not_authenticate_or_restore_account',
      (tester) async {
    final storage = SpyStorage();
    // A stale PREVIOUS account session exists on this device — registration
    // must revoke/wipe it, never reuse it.
    storage.values['ecoloop_session'] = 'old-account-jwt';
    final auth = SpyAuthRepository(storage, hasStoredSession: true);
    final (container, widget) = _app(auth);
    addTearDown(container.dispose);

    await tester.pumpWidget(widget);
    await tester.pumpAndSettle(); // bootstrap: restored old session gated

    // The restored OLD session shows the explicit gate, not Home.
    expect(find.byType(AppShell), findsNothing);
    expect(find.textContaining('Welcome back'), findsWidgets);

    await tester.ensureVisible(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);

    await _fillRegisterForm(tester);
    await tester.ensureVisible(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    // The register screen keeps its busy spinner alive behind the modal
    // dialog, so settle manually with discrete frames instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // Success dialog, then explicit navigation to Login.
    expect(find.text('Account created'), findsOneWidget);
    expect(find.textContaining('starts with 0 points'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Log in')));
    await tester.pumpAndSettle();

    // ---- the contract -------------------------------------------------
    expect(auth.registerCalls, 1);
    expect(auth.loginCalls, 0, reason: 'login must never be auto-called');
    expect(find.byType(LoginScreen), findsOneWidget,
        reason: 'navigation lands on Login');
    expect(find.byType(AppShell), findsNothing, reason: 'Home is NOT shown');

    final session = container.read(sessionProvider);
    expect(session.isAuthenticated, isFalse,
        reason: 'auth state remains UNAUTHENTICATED');
    expect(session.status, SessionStatus.anonymous);
    expect(session.user, isNull);

    expect(storage.writes, isEmpty,
        reason: 'NO access token may be stored after registration');
    expect(storage.deletes, contains('ecoloop_session'),
        reason: 'the previous stored session must have been wiped');
    expect(storage.values.containsKey('ecoloop_session'), isFalse,
        reason: 'no refresh/access token survives registration');

    // The Login form is EMPTY — no auto-submit ever fires.
    final emailField = tester
        .widget<TextFormField>(find.byKey(const ValueKey('Email address')));
    final passwordField =
        tester.widget<TextFormField>(find.byKey(const ValueKey('Password')));
    expect(emailField.controller!.text, isEmpty);
    expect(passwordField.controller!.text, isEmpty);
    expect(auth.loginCalls, 0);
  });

  testWidgets('manual_login_after_registration_does_not_auto_authenticate',
      (tester) async {
    final storage = SpyStorage();
    final auth = SpyAuthRepository(storage);
    final (container, widget) = _app(auth);
    addTearDown(container.dispose);

    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    // Register first.
    await tester.ensureVisible(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    await _fillRegisterForm(tester);
    await tester.ensureVisible(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Account created'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Log in')));
    await tester.pumpAndSettle();
    expect(auth.loginCalls, 0); // still nothing automatic

    // The user NOW types their credentials manually and presses Log in.
    await tester.enterText(find.byKey(const ValueKey('Email address')),
        'reg.test@uni.edu');
    await tester.ensureVisible(find.text('Log in').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('Password')), 'secret99');
    await tester.tap(find.text('Log in').last);
    await tester.pumpAndSettle();

    // Exactly ONE explicit /auth/login call created the session.
    expect(auth.loginCalls, 1);
    final session = container.read(sessionProvider);
    expect(session.isAuthenticated, isTrue);
    expect(session.autoRestored, isFalse,
        reason: 'a manual login is an explicit session, never autoRestored');
    expect(storage.writes, ['ecoloop_session'],
        reason: 'only the LOGIN stores a token');
    expect(find.byType(AppShell), findsOneWidget, reason: 'Home is displayed');
  });

  testWidgets('session_restoration_does_not_override_manual_auth_navigation',
      (tester) async {
    final storage = SpyStorage();
    storage.values['ecoloop_session'] = 'valid-stored-jwt';
    final auth = SpyAuthRepository(storage, hasStoredSession: true);
    final (container, widget) = _app(auth);
    addTearDown(container.dispose);

    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    // Valid stored session -> "Welcome back" gate; Home is NOT entered.
    expect(find.textContaining('Welcome back'), findsWidgets);
    expect(find.byType(AppShell), findsNothing);

    // Choose Create account: the old session must not hijack it.
    await tester.ensureVisible(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget,
        reason: 'restoration must not yank the user out of Create Account');
    expect(find.byType(AppShell), findsNothing);

    // Back out manually: the explicit gate is still there, still not Home.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);

    // Only an explicit Continue enters the app.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);
  });
}
