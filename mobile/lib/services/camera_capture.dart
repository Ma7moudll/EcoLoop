import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart';

/// Result of a real camera capture: the exact JPEG bytes produced by the
/// device camera plus the SHA-256 fingerprint computed on-device. The hash is
/// the identity token: the Android E2E compares it against what the backend
/// reports it received (debug fingerprint route) to prove byte-for-byte
/// capture → upload. It is never shown in the normal UI.
class CapturedFrame {
  final List<int> jpegBytes;
  final String sha256Hex;

  const CapturedFrame({required this.jpegBytes, required this.sha256Hex});
}

/// Shared camera capture path used by the scan screen and the camera E2E
/// integration test. Encapsulates: enumerate cameras → pick the rear one →
/// initialize → capture a JPEG → hash it. Both callers go through this exact
/// code so the bytes the API receives are proven to be camera output.
class CameraCaptureService {
  static const _jpegMime = 'image/jpeg';

  /// Enumerates cameras and initializes the rear (back) camera if present.
  /// Throws [CameraException] with the plugin's error code on failure (e.g.
  /// `CameraAccessDenied` when permission was refused).
  static Future<CameraController> initialize() async {
    final cameras = await availableCameras();
    final back = cameras
            .where((c) => c.lensDirection == CameraLensDirection.back)
            .toList()
        .firstOrNull;
    final description = back ?? cameras.first;
    final controller = CameraController(description, ResolutionPreset.medium);
    await controller.initialize();
    return controller;
  }

  /// Captures one frame from an initialized [controller], reads the exact
  /// JPEG bytes and returns them along with their SHA-256.
  static Future<CapturedFrame> capture(CameraController controller) async {
    final file = await controller.takePicture();
    final bytes = await file.readAsBytes();
    return CapturedFrame(jpegBytes: bytes, sha256Hex: fingerprint(bytes));
  }

  /// Pure SHA-256 hex fingerprint of arbitrary bytes (unit-testable without a
  /// camera). The Android E2E compares this against the backend's fingerprint
  /// of the bytes it received.
  static String fingerprint(List<int> bytes) =>
      sha256.convert(bytes).toString();

  static String mimeType() => _jpegMime;
}