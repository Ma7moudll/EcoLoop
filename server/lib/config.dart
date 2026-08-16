import 'dart:io';
import 'dart:math';

/// Runtime configuration for the Recycle Vision backend, read from the
/// process environment. Secrets are never committed; the JWT secret is
/// auto-generated and persisted into the (git-ignored) data directory the
/// first time the server boots.
class ServerConfig {
  final int port;
  final String dataDir;
  final bool demoMode;
  final String? aiApiUrl;
  final String? aiApiKey;
  final String jwtSecret;
  final Duration predictionLifetime;
  final Duration depositLifetime;

  const ServerConfig({
    required this.port,
    required this.dataDir,
    required this.demoMode,
    required this.aiApiUrl,
    required this.aiApiKey,
    required this.jwtSecret,
    required this.predictionLifetime,
    required this.depositLifetime,
  });

  factory ServerConfig.fromEnv(Map<String, String> env) {
    final dataDir = env['DATA_DIR'] ?? 'data';

    // Demo mode defaults to ON so the app is usable stand-alone. Real AI /
    // hardware only runs when explicitly disabled.
    final demoMode = (env['DEMO_MODE'] ?? 'true').toLowerCase() == 'true';

    return ServerConfig(
      port: int.tryParse(env['PORT'] ?? '') ?? 8080,
      dataDir: dataDir,
      demoMode: demoMode,
      aiApiUrl: env['AI_API_URL'],
      aiApiKey: env['AI_API_KEY'],
      jwtSecret: resolveJwtSecret(
        Directory(dataDir),
        env['JWT_SECRET'],
      ),
      predictionLifetime: const Duration(minutes: 5),
      depositLifetime: const Duration(minutes: 5),
    );
  }

  /// Uses the provided secret or generates + persists a random one so that
  /// tokens survive restarts without committing any secret to the repo.
  static String resolveJwtSecret(Directory dataDir, String? override) {
    if (override != null && override.isNotEmpty) return override;

    final file = File('${dataDir.path}.jwt_secret');
    if (file.existsSync()) {
      final existing = file.readAsStringSync().trim();
      if (existing.isNotEmpty) return existing;
    }
    dataDir.createSync(recursive: true);
    final secret = 'rv_${List.generate(32, (_) => _randChar()).join()}';
    file.writeAsStringSync(secret, flush: true);
    return secret;
  }

  static String _randChar() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return chars[_random.nextInt(chars.length)];
  }
}

final _random = _SecureRandom();

/// A Random backed by the OS CSPRNG (for secret generation only).
class _SecureRandom {
  final _rand = Random.secure();
  int nextInt(int max) => _rand.nextInt(max);
}