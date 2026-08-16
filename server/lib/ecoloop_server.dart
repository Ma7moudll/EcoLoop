import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'config.dart';
import 'seed.dart';
import 'server.dart';
import 'store.dart';

/// Bootstraps the backend: builds the configuration, opens the [DataStore],
/// seeds it on first boot, and wires the HTTP handler.
class EcoLoopServer {
  final ServerConfig config;
  final DataStore store;

  const EcoLoopServer(this.config, this.store);

  static Future<EcoLoopServer> create(Map<String, String> env) async {
    final config = ServerConfig.fromEnv(env);
    final store = await DataStore.create(config.dataDir);
    final wasSeeded = store.isSeeded;
    if (!wasSeeded) {
      await seedStore(store);
    }
    return EcoLoopServer(config, store);
  }

  Future<void> start() async {
    final dir = Directory(config.dataDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    store.setConfig(config);
    final handler = buildHandler(config, store);
    final server =
        await shelf_io.serve(handler, InternetAddress.anyIPv4, config.port);
    print(
        '✅ EcoLoop backend listening on http://${server.address.host}:${server.port} '
        '(demo=${config.demoMode ? 'ON' : 'OFF'})');
    print('   Data directory: ${p.canonicalize(config.dataDir)}');
  }
}