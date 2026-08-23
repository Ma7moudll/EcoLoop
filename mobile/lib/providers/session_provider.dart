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
  /// user so returning users skip typing their password. The restored
  /// session is marked [SessionState.autoRestored] — the app shows an
  /// explicit "Continue as …" confirmation instead of silently opening
  /// someone's account.
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
      state = SessionState.ready(user, autoRestored: true);
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

  /// The user tapped "Continue as …" on a restored session — from here on
  /// the app may enter the shell directly.
  void continueRestored() {
    final user = state.user;
    if (user != null) state = SessionState.ready(user);
  }

  Future<void> login(String email, String password) async {
    final repo = ref.read(authRepositoryProvider);
    final (_, user) = await repo.login(email, password);
    state = SessionState.ready(user);
  }

  /// Creates the account. Registration NEVER authenticates: no token is
  /// stored, no session is established, and any pre-existing (possibly
  /// another user's) stored session is revoked and wiped by the repository
  /// before the request. The state remains anonymous; the UI then sends the
  /// user to Login for an explicit sign-in.
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String facultyId,
    required String studentCode,
  }) async {
    final repo = ref.read(authRepositoryProvider);
    await repo.register(
      name: name,
      email: email,
      password: password,
      facultyId: facultyId,
      studentCode: studentCode,
    );
    if (state.status != SessionStatus.anonymous) {
      state = const SessionState.anonymous();
    }
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).clearSession();
    state = const SessionState.anonymous();
  }

  /// Edit profile (name / faculty). Returns the updated user.
  Future<AppUser> updateProfile({String? name, String? facultyId}) async {
    final repo = ref.read(authRepositoryProvider);
    final user = await repo.updateProfile(name: name, facultyId: facultyId);
    state = SessionState.ready(user);
    return user;
  }

  /// Change password. The backend revokes every outstanding token, so the
  /// app signs out and returns to the login screen.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await ref
        .read(authRepositoryProvider)
        .changePassword(
          currentPassword: currentPassword,
          newPassword: newPassword,
        );
    state = const SessionState.anonymous();
  }

  /// Upload a new profile photo and refresh the session user.
  Future<void> uploadAvatar(String filePath) async {
    final repo = ref.read(authRepositoryProvider);
    final user = await repo.uploadAvatar(filePath);
    state = SessionState.ready(user);
  }

  /// Remove the profile photo and refresh the session user.
  Future<void> removeAvatar() async {
    final repo = ref.read(authRepositoryProvider);
    final user = await repo.removeAvatar();
    state = SessionState.ready(user);
  }
}

enum SessionStatus { initial, loading, ready, anonymous, error }

class SessionState {
  final SessionStatus status;
  final AppUser? user;
  final String? error;

  /// True when the session was restored from device storage at startup and
  /// the user has not explicitly confirmed it yet. The UI must ask before
  /// entering the app (never silently open a stored account).
  final bool autoRestored;

  const SessionState._(this.status, this.user, this.error,
      {this.autoRestored = false});

  const SessionState.initial() : this._(SessionStatus.initial, null, null);
  const SessionState.loading() : this._(SessionStatus.loading, null, null);
  const SessionState.anonymous() : this._(SessionStatus.anonymous, null, null);

  SessionState.error(ApiException e)
      : this._(SessionStatus.error, null, e.message);

  SessionState.ready(AppUser user, {bool autoRestored = false})
      : this._(SessionStatus.ready, user, null, autoRestored: autoRestored);

  bool get isAuthenticated => status == SessionStatus.ready;
}

final sessionProvider =
    NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);