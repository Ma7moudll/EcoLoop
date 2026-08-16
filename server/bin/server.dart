import 'dart:io';

import 'package:server/ecoloop_server.dart';

Future<void> main() async {
  final server = await EcoLoopServer.create(Platform.environment);
  await server.start();
}