import 'package:flutter/foundation.dart';

/// Compile-time + runtime configuration.
///
/// Pass with `--dart-define`:
///   # Android emulator (host loopback is 10.0.2.2)
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1
///   # Physical device (LAN IP of the dev machine)
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8080/api/v1
///
/// If no explicit `API_BASE_URL` is provided, the default **automatically maps
/// the host for the Android emulator** (`http://10.0.2.2:8080/api/v1`), where
/// `10.0.2.2` is the emulator's alias for the host machine's loopback. On a
/// physical device there is no such alias — pass the LAN IP explicitly.
abstract final class AppConfig {
  static const _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

  /// Effective API base URL. Android debug builds default to the emulator host
  /// mapping; everything else defaults to localhost. An explicit
  /// `--dart-define=API_BASE_URL=...` always wins (see header docs).
  static String get apiBaseUrl {
    if (_apiBaseUrlOverride.isNotEmpty) return _apiBaseUrlOverride;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android &&
        kDebugMode) {
      return 'http://10.0.2.2:8080/api/v1';
    }
    return 'http://localhost:8080/api/v1';
  }
}