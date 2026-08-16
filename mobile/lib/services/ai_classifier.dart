import 'package:shared/shared.dart';

import '../core/api_client.dart';

/// AI classifier abstraction. The UI only ever consumes the typed [Prediction]
/// contract — the concrete implementation (real API vs mock) is irrelevant to
/// screens, and the DEMO badge is driven by `prediction.source`.
abstract class AiClassifier {
  Future<Prediction> predictImage(List<int> jpegBytes);
}

/// Production implementation: multipart upload to `POST /api/v1/ai/predict`.
/// The backend decides between real AI and demo mock; either way the response
/// shape is identical.
class ApiAiClassifier implements AiClassifier {
  final ApiClient _api;

  ApiAiClassifier(this._api);

  @override
  Future<Prediction> predictImage(List<int> jpegBytes) async {
    final body = await _api.postMultipart('/ai/predict', jpegBytes);
    return Prediction.fromJson(body);
  }
}

/// Offline preview implementation used ONLY when no backend is configured.
/// Returns a typed prediction without any network/server involvement. It is
/// never allowed to award points — deposits still require the backend, so a
/// session created from this prediction is impossible without a server.
class MockAiClassifier implements AiClassifier {
  @override
  Future<Prediction> predictImage(List<int> jpegBytes) async {
    final cls = _pick(jpegBytes.length);
    return Prediction(
      predictionId: 'pred_local',
      operationId: 'OP-LOCAL',
      predictedClass: cls,
      confidence: 0.96,
      confidenceLevel: ConfidenceLevel.high,
      recyclable: cls.isRecyclable,
      destinationPosition: positionForClass(cls),
      potentialPoints: compartmentForClass(cls).potentialPoints,
      expiresAt: DateTime.now().add(const Duration(minutes: 5)).toUtc(),
      source: 'demo',
    );
  }

  WasteClass _pick(int seed) =>
      seed.isEven ? WasteClass.plastic : WasteClass.metal;
}