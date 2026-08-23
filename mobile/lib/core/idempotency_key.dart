import 'dart:math';

/// One-off reference for a rewards redemption. The server enforces one
/// redemption per key per user, so retrying a timed-out request can never
/// double-spend. Random 32-hex chars (crypto-grade, no extra dependency).
String newIdempotencyKey() {
  final rnd = Random.secure();
  return List.generate(32, (_) => rnd.nextInt(16).toRadixString(16)).join();
}
