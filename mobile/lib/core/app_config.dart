import 'package:flutter/foundation.dart';

/// Compile-time + runtime configuration.
///
/// Pass with `--dart-define`:
///   # Android emulator (host loopback is 10.0.2.2)
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1
///   # Physical device or production (HTTPS required in non-debug builds)
///   flutter run --dart-define=API_BASE_URL=https://api.yourdomain.com/api/v1
///
/// Non-debug builds REQUIRE an explicit HTTPS API_BASE_URL — the app will
/// throw a StateError at startup if one is not provided.
abstract final class AppConfig {
  static const _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

  /// Effective API base URL.
  ///
  /// - Debug Android: defaults to `http://10.0.2.2:8080/api/v1` (emulator alias).
  /// - Debug other: defaults to `http://localhost:8080/api/v1`.
  /// - Non-debug: throws if `API_BASE_URL` is not set or is not HTTPS.
  static String get apiBaseUrl {
    if (_apiBaseUrlOverride.isNotEmpty) {
      // Enforce HTTPS for non-debug builds.
      if (!kDebugMode && !_apiBaseUrlOverride.startsWith('https://')) {
        throw StateError(
          'API_BASE_URL must use HTTPS in non-debug builds. '
          'Provide --dart-define=API_BASE_URL=https://...',
        );
      }
      return _apiBaseUrlOverride;
    }

    // Debug fallbacks — never reachable in release builds because the assert
    // below fires first.
    assert(
      kDebugMode,
      'API_BASE_URL must be set via --dart-define for non-debug builds. '
      'Example: --dart-define=API_BASE_URL=https://api.yourdomain.com/api/v1',
    );

    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        kDebugMode) {
      return 'http://10.0.2.2:8080/api/v1';
    }
    return 'http://localhost:8080/api/v1';
  }
}
