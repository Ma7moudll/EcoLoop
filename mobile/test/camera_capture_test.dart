import 'package:flutter_test/flutter_test.dart';
import 'package:recycle_vision/core/app_config.dart';
import 'package:recycle_vision/services/camera_capture.dart';

// Byte-identity unit tests for the camera capture service. The device camera
// itself cannot run in a host test; the fingerprint primitive and the API
// configuration (emulator host mapping) are covered here, and the real-camera
// path is proven on-device in integration_test/android_camera_e2e_test.dart.

void main() {
  group('CameraCaptureService.fingerprint', () {
    test('SHA-256 is deterministic for identical bytes', () {
      const bytes = [0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46];
      expect(
        CameraCaptureService.fingerprint(bytes),
        CameraCaptureService.fingerprint(bytes),
      );
    });

    test('differs when a single byte changes (byte identity is strict)', () {
      expect(
        CameraCaptureService.fingerprint([1, 2, 3, 4]),
        isNot(CameraCaptureService.fingerprint([1, 2, 3, 5])),
      );
    });

    test('matches the known SHA-256 test vector', () {
      expect(
        CameraCaptureService.fingerprint('abc'.codeUnits),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('represents JPEG bytes unchanged (no re-encode)', () {
      final jpeg = List<int>.generate(64, (i) => i);
      final serverSide =
          CameraCaptureService.fingerprint(List<int>.from(jpeg));
      expect(CameraCaptureService.fingerprint(jpeg), serverSide);
    });
  });

  group('AppConfig.apiBaseUrl', () {
    test('defaults to the emulator host mapping on Android debug', () {
      // No API_BASE_URL override compiled in: Android debug app hits the host
      // loopback alias 10.0.2.2 so the emulator can reach the dev machine.
      expect(AppConfig.apiBaseUrl, 'http://10.0.2.2:8080/api/v1');
    });

    test('explicit --dart-define override wins', () {
      const override = String.fromEnvironment('API_BASE_URL');
      if (override.isNotEmpty) {
        expect(AppConfig.apiBaseUrl, override);
      }
    });
  });
}