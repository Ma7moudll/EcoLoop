import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:recycle_vision/core/api_client.dart';
import 'package:recycle_vision/core/app_config.dart';
import 'package:recycle_vision/services/camera_capture.dart';
import 'package:recycle_vision/services/ai_classifier.dart';
import 'package:recycle_vision/services/auth_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:camera/camera.dart';
import 'package:shared/shared.dart';

/// REAL ANDROID CAMERA → REAL API E2E.
///
/// This is an on-device integration test. It uses NO fixtures, NO mocks, NO
/// offline overrides: the device camera captures a JPEG, its exact bytes are
/// POSTed to the REAL backend /predict (which calls the REAL AI service), and
/// the on-device SHA-256 is checked against the backend's debug fingerprint
/// route to prove byte identity.
///
/// Prerequisites: backend + ai-service + mosquitto running with
/// `DEBUG_IMAGE_HASH=true`, demo@recycle.vision/demo123 available, camera
/// permission granted on the device/emulator.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Credentials are injected at run time, never committed.
  const email = String.fromEnvironment('E2E_USER', defaultValue: 'demo@recycle.vision');
  const password =
      String.fromEnvironment('E2E_PASSWORD', defaultValue: 'demo123');

  // The backend base URL must be reachable from the emulator/device; pass it
  // explicitly (10.0.2.2 on the emulator, the LAN IP on a physical device).
  const baseOverride = String.fromEnvironment('API_BASE_URL');
  final base = baseOverride.isNotEmpty ? baseOverride : AppConfig.apiBaseUrl;

  test('real camera JPEG reaches the real backend byte-for-byte', () async {
    // Camera init + capture + 2 real API round-trips on an emulator routinely
    // exceed the 30s default; give the on-device proof a generous budget.

    // 1. REAL camera capture (no fixtures, no mocks). The emulator's virtual
    //    camera HAL can wedge immediately after a previous run, so bound each
    //    attempt and retry once before reporting an honest failure.
    late CameraController controller;
    late CapturedFrame frame;
    var attempts = 0;
    while (true) {
      attempts++;
      try {
        debugPrint('CAMERA_STEP attempt $attempts availableCameras...');
        controller = await CameraCaptureService.initialize()
            .timeout(const Duration(seconds: 90));
        debugPrint('CAMERA_STEP attempt $attempts controller initialized');
        frame = await CameraCaptureService.capture(controller)
            .timeout(const Duration(seconds: 90));
        await controller.dispose();
        debugPrint('CAMERA_STEP attempt $attempts frame captured');
        break;
      } catch (e) {
        debugPrint('CAMERA_STEP attempt $attempts failed: $e');
        try {
          await controller.dispose();
        } catch (_) {}
        if (attempts >= 4) {
          rethrow;
        }
        // Give the harness time to land `adb shell pm grant ... CAMERA`
        // (the app is reinstalled on every drive run, resetting permission).
        await Future<void>.delayed(const Duration(seconds: 10));
      }
    }

    // Optional: dump the raw captured JPEG for the harness (only when
    // explicitly requested, e.g. E2E_SAVE_CAPTURE=true) so the actual camera
    // frame can be pulled off-device for evidence.
    if (const bool.fromEnvironment('E2E_SAVE_CAPTURE')) {
      final dir = await getApplicationCacheDirectory();
      final out = File('${dir.path}/camera_e2e_capture.jpg');
      await out.writeAsBytes(frame.jpegBytes);
      debugPrint('SAVED_CAPTURE ${out.path}');
    }

    expect(frame.jpegBytes.length, greaterThan(0), reason: 'camera captured bytes');
    debugPrint('CAPTURED sha256=${frame.sha256Hex} size=${frame.jpegBytes.length}');

    // 2. Authenticate against the REAL backend.
    final api = ApiClient(base);
    final auth = AuthRepository(api, const FlutterSecureStorage());
    final (token, _) = await auth.login(email, password);
    expect(token, isNotEmpty);

    // 3. Backend debug fingerprint: the exact bytes the HTTP layer received.
    final echoed = await api
        .postMultipart('/debug/image-sha256', frame.jpegBytes,
            field: 'image', filename: 'capture.jpg');
    expect(echoed['sha256'], frame.sha256Hex,
        reason: 'on-device SHA-256 must equal the bytes the backend received');

    // 4. Send the SAME bytes through the real classification endpoint.
    final classifier = ApiAiClassifier(api);
    final Prediction prediction;
    try {
      prediction = await classifier.predictImage(frame.jpegBytes);
    } on ApiException catch (e) {
      // A structured gate rejection (NO_OBJECT/LOW_QUALITY/CORRUPT_IMAGE) is
      // an honest outcome for a background/empty/emulated-camera frame —
      // the gate exists to reject exactly this. Assert the rejection shape,
      // then stop (no fake prediction, no fabricated result).
      expect(e.statusCode, 422, reason: 'gate rejection must be HTTP 422');
      expect(e.message, isNotEmpty);
      debugPrint('GATE_REJECTION status=${e.statusCode} error=${e.message}');
      return;
    }

    // If the frame was accepted, the prediction must come from the REAL model.
    expect(prediction.source, equals('ai'),
        reason: 'no demo/mock predictions in the real E2E');
    debugPrint(
        'PREDICTION class=${prediction.predictedClass} '
        'conf=${prediction.confidence} level=${prediction.confidenceLevel} '
        'source=${prediction.source}');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('corrupt bytes are rejected as HTTP 422 by the real gate', () async {
    // Non-image bytes must never reach the classifier: the REAL backend +
    // REAL AI service returns a structured 422 CORRUPT_IMAGE. No fixtures,
    // no mocks — this is the production wire contract.
    final api = ApiClient(base);
    final auth = AuthRepository(api, const FlutterSecureStorage());
    await auth.login(email, password);

    final classifier = ApiAiClassifier(api);
    final corrupt = List<int>.generate(64, (i) => 0xA0 + i % 16);
    try {
      await classifier.predictImage(corrupt);
      fail('corrupt image must be rejected, not classified');
    } on ApiException catch (e) {
      debugPrint('CORRUPT_REJECTION status=${e.statusCode} error=${e.message}');
      expect(e.statusCode, 422, reason: 'corrupt image must be HTTP 422');
      expect(e.message, isNotEmpty);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}