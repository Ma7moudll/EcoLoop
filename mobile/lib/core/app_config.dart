/// Compile-time + runtime configuration.
///
/// Pass with `--dart-define`:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8080/api/v1
///   flutter run --dart-define=DEMO_MODE=true
///
/// `DEMO_MODE` is a cosmetic flag that shows the subtle DEMO indicator; the
/// authoritative decision to serve mock AI / simulated station responses lives
/// on the backend (`DEMO_MODE` env on the server).
abstract final class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/api/v1',
  );

  static const demoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: true);

  /// Minimum weight (grams) a deposit must show for the backend to accept it.
  /// Mirrors the backend constant — used only for demo UX copy.
  static const minDepositWeightGrams = 1.0;

  /// Simulated weight reported by the station during demo-mode deposits. In
  /// real mode this comes from the hardware load cell.
  static const simulatedWeightGrams = 18.4;
}