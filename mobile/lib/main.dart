import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/app_config.dart';
import 'offline/offline_backend.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final overrides = <Override>[];
  if (AppConfig.offlineMode) {
    // No backend available: run the whole app on local fakes (device preview).
    overrides.addAll(offlineOverrides());
  }

  runApp(ProviderScope(
    overrides: overrides,
    child: const RecycleVisionApp(),
  ));
}