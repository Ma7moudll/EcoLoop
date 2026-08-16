import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared/shared.dart';

import 'json_file.dart';
import 'store.dart';

/// PBKDF2-SHA256 password hashing with a per-user salt. Uses a high iteration
/// count so stored hashes are not trivially brute-forced. Lowered in tests.
int pbkdf2Iterations = 120000;

List<int> _hmacSha256(List<int> key, List<int> data) =>
    Hmac(sha256, key).convert(data).bytes;

List<int> _intToBigEndian(int value) => [
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ];

/// PBKDF2 with HMAC-SHA256 (RFC 2898). Returns [dkLen] bytes.
/// Implemented in-place to avoid a native dependency OR pulling in a heavy
/// password library for the MVP.
List<int> pbkdf2Sha256({
  required List<int> password,
  required List<int> salt,
  required int iterations,
  int dkLen = 32,
}) {
  const hLen = 32;
  final blocks = (dkLen + hLen - 1) ~/ hLen;
  final result = <int>[];
  for (var block = 1; block <= blocks; block++) {
    final blockBytes = [...salt, ..._intToBigEndian(block)];
    var u = _hmacSha256(password, blockBytes);
    final t = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = _hmacSha256(password, u);
      for (var b = 0; b < hLen; b++) {
        t[b] ^= u[b];
      }
    }
    result.addAll(t);
  }
  return result.take(dkLen).toList();
}

String pbkdf2Hash(String password, String salt) {
  final derived = pbkdf2Sha256(
    password: utf8.encode(password),
    salt: utf8.encode(salt),
    iterations: pbkdf2Iterations,
  );
  return base64Encode(derived);
}

String _randomSalt() =>
    List.generate(16, (_) => _rng.nextInt(16).toRadixString(16)).join();

final _rng = Random.secure();

/// Hand-rolled HS256 JWT (header.payload.signature). Kept dependency-free and
/// intentionally simple: payload only carries `sub` + `exp`.
bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

class Jwt {
  final String secret;

  Jwt(this.secret);

  static String _b64(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static String _b64Json(Map<String, dynamic> json) =>
      _b64(utf8.encode(jsonEncode(json)));

  String sign({required String subject, Duration lifetime = const Duration(days: 1)}) {
    final header = _b64Json({'alg': 'HS256', 'typ': 'JWT'});
    final payload = _b64Json({
      'sub': subject,
      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'exp': DateTime.now().add(lifetime).millisecondsSinceEpoch ~/ 1000,
    });
    final signature = _b64(
      Hmac(sha256, utf8.encode(secret))
          .convert(utf8.encode('$header.$payload'))
          .bytes,
    );
    return '$header.$payload.$signature';
  }

  /// Returns the subject if the token is structurally valid, correctly signed
  /// and not expired, otherwise `null`.
  String? verify(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final [header, payload, signature] = parts;

      final expected = _b64(
        Hmac(sha256, utf8.encode(secret))
            .convert(utf8.encode('$header.$payload'))
            .bytes,
      );
      if (!_constantTimeEquals(utf8.encode(expected), utf8.encode(signature))) {
        return null;
      }

      final headerJson = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(header))),
      ) as Map<String, dynamic>;
      if (headerJson['alg'] != 'HS256') return null;

      final payloadJson = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(payload))),
      ) as Map<String, dynamic>;
      final exp = payloadJson['exp'] as int?;
      if (exp == null) return null;
      if (DateTime.fromMillisecondsSinceEpoch(exp * 1000)
          .isBefore(DateTime.now())) {
        return null;
      }
      return payloadJson['sub'] as String?;
    } catch (_) {
      return null;
    }
  }
}

/// Auth session abstraction. The JWT is returned to the client (stored in
/// secure storage on-device) and sent as `Authorization: Bearer` on requests.
/// The server is the only authority that mints/verifies tokens.
class AuthService {
  final DataStore store;
  final Jwt jwt;

  AuthService(this.store, {required String secret}) : jwt = Jwt(secret);

  static final RegExp _emailRe =
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Registers a new user. Returns an error message string or `null` on
  /// success. Passwords are hashed before any persistence.
  String? register({
    required String name,
    required String email,
    required String password,
    String? facultyId,
  }) {
    final trimmedEmail = email.trim().toLowerCase();
    if (name.trim().isEmpty) return 'Name is required.';
    if (!_emailRe.hasMatch(trimmedEmail)) return 'Enter a valid email address.';
    if (password.length < 6) return 'Password must be at least 6 characters.';
    if (store.userByEmail(trimmedEmail) != null) {
      return 'An account with this email already exists.';
    }

    final faculty = store.facultyById(facultyId ?? 'f-eng') ??
        store.faculties.first;
    final salt = _randomSalt();
    final record = UserRecord(
      user: AppUser(
        id: Ids.record(),
        studentCode: 'S-${DateTime.now().year}-${_rng.nextInt(9000) + 1000}',
        name: name.trim(),
        facultyId: faculty.id,
        facultyName: faculty.name,
        points: 0,
      ),
      email: trimmedEmail,
      passwordHash: pbkdf2Hash(password, salt),
      passwordSalt: salt,
      completedChallengeIds: const [],
    );
    store.users[record.user.id] = record;
    store.emailIndex[trimmedEmail] = record.user.id;
    return null;
  }

  /// Validates credentials; on success returns (token, user) else null.
  ({String token, AppUser user})? login(String email, String password) {
    final record = store.userByEmail(email.trim().toLowerCase());
    if (record == null) return null;
    final hash = pbkdf2Hash(password, record.passwordSalt);
    if (hash != record.passwordHash) return null;
    final token = jwt.sign(subject: record.user.id);
    return (token: token, user: record.user);
  }

  AppUser? userFromToken(String token) {
    final id = jwt.verify(token);
    if (id == null) return null;
    return store.userById(id)?.user;
  }
}