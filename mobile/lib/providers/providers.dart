import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/api_client.dart';
import '../core/app_config.dart';
import '../services/ai_classifier.dart';
import '../services/auth_repository.dart';
import '../services/data_repository.dart';

/// Lowest-level providers. Everything more specific builds on these.

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(AppConfig.apiBaseUrl);
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(secureStorageProvider),
  );
});

final aiClassifierProvider = Provider<AiClassifier>((ref) {
  return ApiAiClassifier(ref.watch(apiClientProvider));
});

final dataRepositoryProvider = Provider<DataRepository>((ref) {
  return DataRepository(ref.watch(apiClientProvider));
});

final depositRepositoryProvider = Provider<DepositRepository>((ref) {
  return DepositRepository(ref.watch(apiClientProvider));
});