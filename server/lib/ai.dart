import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

import 'config.dart';
import 'json_file.dart';
import 'store.dart';

/// AI prediction provider. The response shape is EXACTLY the typed `Prediction`
/// contract — mocked and real predictions are indistinguishable to callers
/// (only `source` differs, which powers the DEMO badge).
class AiService {
  final ServerConfig config;
  final DataStore store;
  final http.Client _client;

  AiService(this.config, this.store, {http.Client? client})
      : _client = client ?? http.Client();

  static const _maxImageBytes = 10 * 1024 * 1024;

  /// Runs a prediction for [imageBytes]. In demo mode a deterministic mock is
  /// used; otherwise the image is forwarded to the configured real AI API.
  Future<Prediction> predict(List<int> imageBytes) async {
    if (config.demoMode || config.aiApiUrl == null) {
      return _mockPredict(imageBytes);
    }
    return _realPredict(imageBytes);
  }

  List<String> _validateImage(List<int> bytes) {
    if (bytes.isEmpty) return ['Image is empty.'];
    if (bytes.length > _maxImageBytes) {
      return ['Image exceeds the 10 MB limit.'];
    }
    return const [];
  }

  Future<Prediction> _mockPredict(List<int> imageBytes) async {
    final errors = _validateImage(imageBytes);
    if (errors.isNotEmpty) {
      throw StateError(errors.join(' '));
    }

    // Seeded by the bytes so repeated uploads are deterministic in tests.
    final seed = imageBytes.fold<int>(0, (a, b) => (a + b) & 0x7fffffff);
    final rand = Random(seed);

    final roll = rand.nextDouble();
    final WasteClass cls;
    if (roll < 0.42) {
      cls = WasteClass.plastic;
    } else if (roll < 0.56) {
      cls = WasteClass.metal;
    } else if (roll < 0.80) {
      cls = WasteClass.paper;
    } else {
      cls = WasteClass.other;
    }

    final confidenceRoll = rand.nextDouble();
    final double confidence;
    if (confidenceRoll < 0.60) {
      confidence = 0.82 + rand.nextDouble() * 0.16; // high
    } else if (confidenceRoll < 0.90) {
      confidence = 0.50 + rand.nextDouble() * 0.29; // medium
    } else {
      confidence = 0.20 + rand.nextDouble() * 0.29; // low
    }

    return _buildPrediction(cls: cls, confidence: confidence, source: 'demo');
  }

  Future<Prediction> _realPredict(List<int> imageBytes) async {
    final errors = _validateImage(imageBytes);
    if (errors.isNotEmpty) {
      return Future.error(StateError(errors.join(' ')));
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${config.aiApiUrl}/api/v1/ai/predict'),
    );
    request.headers['Accept'] = 'application/json';
    if (config.aiApiKey != null) {
      request.headers['Authorization'] = 'Bearer ${config.aiApiKey}';
    }
    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: 'capture.jpg',
        contentType: http.MediaType('image', 'jpeg'),
      ),
    );

    final response = await _client.send(request);
    if (response.statusCode != 200) {
      return Future.error(
        StateError('AI service returned ${response.statusCode}.'),
      );
    }
    final body = await response.stream.bytesToString();
    final json = _decodeJson(body);
    if (json == null) {
      return Future.error(StateError('AI service returned invalid JSON.'));
    }
    return Prediction.fromJson(json);
  }

  Prediction _buildPrediction({
    required WasteClass cls,
    required double confidence,
    required String source,
  }) {
    return Prediction(
      predictionId: Ids.prediction(),
      operationId: Ids.operation(),
      predictedClass: cls,
      confidence: (confidence * 100).roundToDouble() / 100,
      confidenceLevel: confidenceLevelFor(confidence),
      recyclable: cls.isRecyclable,
      destinationPosition: positionForClass(cls),
      potentialPoints: compartmentForClass(cls).potentialPoints,
      expiresAt: DateTime.now().toUtc().add(config.predictionLifetime),
      source: source,
    );
  }
}

Map<String, dynamic>? _decodeJson(String body) {
  try {
    return jsonDecode(body) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}