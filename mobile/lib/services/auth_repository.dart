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

  Future<(String, AppUser)> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final body = await _api.post('/auth/register', data: {
      'name': name,
      'email': email,
      'password': password,
    });
    final token = body['token'] as String;
    final user = AppUser.fromJson(body['user'] as Map<String, dynamic>);
    await persistToken(token);
    return (token, user);
  }

  Future<AppUser> fetchMe() async {
    final body = await _api.get('/auth/me');
    return AppUser.fromJson(body['user'] as Map<String, dynamic>);
  }
}