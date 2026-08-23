import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared/shared.dart';

import '../core/api_client.dart';

/// Real application authentication backed by the backend. The JWT is stored in
/// the device secure store (never in plain localStorage-style storage) and is
/// attached to requests by [ApiClient]. The server remains the only authority
/// that mints and validates tokens.
class AuthRepository {
  static const _tokenKey = 'ecoloop_session';

  final ApiClient _api;
  final FlutterSecureStorage _storage;

  AuthRepository(this._api, this._storage);

  Future<String?> restoreToken() => _storage.read(key: _tokenKey);

  Future<void> persistToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
    _api.setToken(token);
  }

  Future<void> clearSession() async {
    try {
      await _api.post('/auth/logout');
    } catch (_) {
      // Server may be offline; local logout must still succeed.
    }
    await _storage.delete(key: _tokenKey);
    _api.setToken(null);
  }

  Future<(String, AppUser)> login(String email, String password) async {
    final body = await _api.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    final token = body['token'] as String;
    final user = AppUser.fromJson(body['user'] as Map<String, dynamic>);
    await persistToken(token);
    return (token, user);
  }

  /// Creates an account. Registration is account CREATION only — the server
  /// returns no token and this method never establishes a session. Any
  /// pre-existing stored session (possibly another user's) is revoked and
  /// wiped FIRST so it cannot leak into or hijack the new identity.
  Future<AppUser> register({
    required String name,
    required String email,
    required String password,
    required String facultyId,
    required String studentCode,
  }) async {
    await clearSession();
    final body = await _api.post('/auth/register', data: {
      'name': name,
      'email': email,
      'password': password,
      'facultyId': facultyId,
      'studentCode': studentCode,
    });
    // The register response intentionally carries no token. If the server
    // ever sent one, we would still refuse to treat it as a session.
    assert(body['token'] == null,
        'register response must not contain a session token');
    return AppUser.fromJson(body['user'] as Map<String, dynamic>);
  }

  Future<AppUser> fetchMe() async {
    final body = await _api.get('/auth/me');
    return AppUser.fromJson(body['user'] as Map<String, dynamic>);
  }

  /// Change password (requires current password). On success the backend
  /// revokes every outstanding token, so the caller MUST sign back in.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _api.post('/auth/change-password', data: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
    await clearSession();
  }

  /// Edit profile (display name / faculty).
  Future<AppUser> updateProfile({String? name, String? facultyId}) async {
    final body = await _api.patch('/users/me/profile', data: {
      if (name != null) 'name': name,
      if (facultyId != null) 'faculty_id': facultyId,
    });
    return AppUser.fromJson(body['user'] as Map<String, dynamic>);
  }

  /// Upload a new profile photo; returns the updated user (new avatarVersion).
  Future<AppUser> uploadAvatar(String filePath) async {
    final body = await _api.uploadFile('/users/me/avatar', 'file', filePath);
    return AppUser.fromJson(body['user'] as Map<String, dynamic>);
  }

  /// Remove the profile photo.
  Future<AppUser> removeAvatar() async {
    final body = await _api.delete('/users/me/avatar');
    return AppUser.fromJson(body['user'] as Map<String, dynamic>);
  }

  /// Fetch a student's profile photo bytes, or null when they have none.
  Future<Uint8List?> fetchAvatarBytes(String userId, {int version = 0}) async {
    try {
      final bytes =
          await _api.getBytes('/users/avatar/$userId?v=$version');
      return bytes.isEmpty ? null : Uint8List.fromList(bytes);
    } on ApiException catch (e) {
      if (e.isUnauthorized) rethrow;
      return null;
    }
  }
}