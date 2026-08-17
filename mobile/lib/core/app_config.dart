import 'package:flutter/foundation.dart';

/// Compile-time + runtime configuration.
///
/// Pass with `--dart-define`:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8080/api/v1
///   flutter run --dart-define=DEMO_MODE=true
///   flutter run --dart-define=OFFLINE_MODE=true   (no backend required)
///
/// `DEMO_MODE` is a cosmetic flag that shows the subtle DEMO indicator; the
/// authoritative decision to serve mock AI / simulated station responses lives
/// on the backend (`DEMO_MODE` env on the server).
///
/// `OFFLINE_MODE` replaces every repository with local in-memory fakes so the
/// app is fully navigable without a running backend. It is a developer
/// preview: pre-signed-in, mock AI, simulated deposit + points isolated behind
/// the DEMO badge. Real points still only ever come from the backend.
abstract final class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/api/v1',
  );

  static const demoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: true);

  /// Whether to run fully offline with local fakes (no backend needed).
  static const offlineMode =
      bool.fromEnvironment('OFFLINE_MODE', defaultValue: false);

  /// Even offline, API calls are never made; this mirrors the backend base URL
  /// for display purposes only.
  static const apiBaseUrlForDisplay = kDebugMode ? 'http://10.0.2.2:8080/api/v1' : apiBaseUrl;

  /// Minimum weight (grams) a deposit must show for the backend to accept it.
  /// Mirrors the backend constant — used only for demo UX copy.
  static const minDepositWeightGrams = 1.0;

  /// Simulated weight reported by the station during demo-mode deposits. In
  /// real mode this comes from the hardware load cell.
  static const simulatedWeightGrams = 18.4;
}