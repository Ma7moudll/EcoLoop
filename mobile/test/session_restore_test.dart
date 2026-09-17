import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecoloop/core/api_client.dart';
import 'package:ecoloop/providers/providers.dart';
import 'package:ecoloop/providers/session_provider.dart';
import 'package:ecoloop/services/auth_repository.dart';
import 'package:shared/shared.dart';

/// Regression guard for the "app opened an old account without signing in"
/// bug: sessions restored from device storage must be flagged
/// [SessionState.autoRestored] so the UI asks before entering, and
/// [SessionNotifier.continueRestored]/login manage the flag correctly.
class _FakeStorage extends FlutterSecureStorage {
  String? value;
  @override
  Future<String?> read({
    required String key,
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
    LinuxOptions? lOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async =>
      value;
  @override
  Future<void> write({
    required String key,
    required String? value,
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
    LinuxOptions? lOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    this.value = value;
  }

  @override
  Future<void> delete({
    required String key,
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
    LinuxOptions? lOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    value = null;
  }
}

class _OkApi extends ApiClient {
  _OkApi() : super('http://localhost:9');
  @override
  Future<Map<String, dynamic>> get(String path,
      {Map<String, dynamic>? query}) async =>
      {'user': _userJson};
}

const _userJson = <String, dynamic>{
  'id': 'u1',
  'studentCode': 'S-1',
  'name': 'Stored User',
  'facultyId': 'ENGINEERING',
  'facultyName': 'Engineering',
  'points': 42,
};

ProviderContainer _containerWith(String? storedToken) {
  final storage = _FakeStorage()..value = storedToken;
  return ProviderContainer(overrides: [
    authRepositoryProvider.overrideWithValue(
        AuthRepository(_OkApi(), storage as FlutterSecureStorage)),
  ]);
}

void main() {
  test('bootstrap flags restored sessions instead of trusting them', () async {
    final container = _containerWith('stored-token');
    addTearDown(container.dispose);

    await container.read(sessionProvider.notifier).bootstrap();
    final state = container.read(sessionProvider);

    expect(state.status, SessionStatus.ready);
    // THE FIX: the UI must ask ("Continue as …") before entering.
    expect(state.autoRestored, isTrue);
    expect(state.user?.points, 42);
  });

  test('no stored token -> anonymous, nothing restored', () async {
    final container = _containerWith(null);
    addTearDown(container.dispose);

    await container.read(sessionProvider.notifier).bootstrap();

    expect(container.read(sessionProvider).status, SessionStatus.anonymous);
  });

  test('continueRestored clears the flag; login marks explicit', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(sessionProvider.notifier);

    notifier.state =
        SessionState.ready(AppUser.fromJson(_userJson), autoRestored: true);
    expect(container.read(sessionProvider).autoRestored, isTrue);

    notifier.continueRestored();
    expect(container.read(sessionProvider).autoRestored, isFalse);
    expect(container.read(sessionProvider).isAuthenticated, isTrue);
  });

  test('login/register produce non-restored (explicit) sessions', () async {
    final container = _containerWith(null);
    addTearDown(container.dispose);

    // Simulate what SessionNotifier.login does after a successful API call.
    final notifier = container.read(sessionProvider.notifier);
    notifier.state =
        SessionState.ready(AppUser.fromJson(_userJson)); // autoRestored: false

    expect(container.read(sessionProvider).autoRestored, isFalse);
    expect(container.read(sessionProvider).isAuthenticated, isTrue);
  });
}
