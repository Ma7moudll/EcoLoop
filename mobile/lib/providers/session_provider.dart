import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../core/api_client.dart';
import 'providers.dart';

/// Tracks the authenticated user. The JWT lives in device secure storage and
/// is attached by [ApiClient] to every request; the server remains the only
/// authority for identity and points.
class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() => const SessionState.initial();

  /// Called once on app start: restores the stored token and refreshes the
  /// user so returning users skip the login screen.
  Future<SessionState> bootstrap() async {
    if (state.status == SessionStatus.ready) return state;
    state = const SessionState.loading();
    final repo = ref.read(authRepositoryProvider);

    final token = await repo.restoreToken();
    if (token == null) {
      state = const SessionState.anonymous();
      return state;
    }
    try {
      final user = await repo.fetchMe();
      state = SessionState.ready(user);
      return state;
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await repo.clearSession();
        state = const SessionState.anonymous();
      } else {
        state = SessionState.error(e);
      }
      return state;
    }
  }

  Future<void> login(String email, String password) async {
    final repo = ref.read(authRepositoryProvider);
    final (_, user) = await repo.login(email, password);
    state = SessionState.ready(user);
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final repo = ref.read(authRepositoryProvider);
    final (_, user) =
        await repo.register(name: name, email: email, password: password);
    state = SessionState.ready(user);
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).clearSession();
    state = const SessionState.anonymous();
  }
}

enum SessionStatus { initial, loading, ready, anonymous, error }

class SessionState {
  final SessionStatus status;
  final AppUser? user;
  final String? error;

  const SessionState._(this.status, this.user, this.error);

  const SessionState.initial() : this._(SessionStatus.initial, null, null);
  const SessionState.loading() : this._(SessionStatus.loading, null, null);
  const SessionState.anonymous() : this._(SessionStatus.anonymous, null, null);

  SessionState.error(ApiException e)
      : this._(SessionStatus.error, null, e.message);

  SessionState.ready(AppUser user)
      : this._(SessionStatus.ready, user, null);

  bool get isAuthenticated => status == SessionStatus.ready;
}

final sessionProvider =
    NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);