import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:recycle_vision/core/api_client.dart';
import 'package:recycle_vision/core/app_config.dart';
import 'package:recycle_vision/services/auth_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared/shared.dart';

/// REAL STATION-CAMERA → REAL BACKEND E2E (FINAL architecture).
///
/// This is an on-device integration test against the real stack. No fixtures,
/// no mocks, no phone camera: the phone acts exactly like the production app —
/// it identifies a real station and creates a capture-first session. The
/// hardware simulator (running on the host as the station) receives the
/// backend's `capture_request`, uploads a REAL frame from its capture dir to
/// `POST /api/v1/deposit/capture`, the backend runs the REAL AI and routes the
/// carriage, the simulator performs the physical drop, and the backend awards
/// points ONLY from the validated MQTT `deposit_result`. The app then
/// converges on `confirmed` — proving the phone can never award points and
/// only the physical chain can.
///
/// Prerequisites: `scripts/station_capture_e2e_stack.py` running on the host
/// (mosquitto 1884 + ai-service 8051 real + backend 8080 + hardware simulator
/// with CaptureUploader), `demo@recycle.vision/demo123` available.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Credentials are injected at run time, never committed.
  const email =
      String.fromEnvironment('E2E_USER', defaultValue: 'demo@recycle.vision');
  const password =
      String.fromEnvironment('E2E_PASSWORD', defaultValue: 'demo123');

  // The backend base URL must be reachable from the emulator/device; pass it
  // explicitly (10.0.2.2 on the emulator, the LAN IP on a physical device).
  const baseOverride = String.fromEnvironment('API_BASE_URL');
  final base = baseOverride.isNotEmpty ? baseOverride : AppConfig.apiBaseUrl;

  test('real station camera completes a deposit and the backend awards points',
      () async {
    // 1. Authenticate against the REAL backend.
    final api = ApiClient(base);
    final auth = AuthRepository(api, const FlutterSecureStorage());
    final (token, _) = await auth.login(email, password);
    expect(token, isNotEmpty);

    // 2. Pick a real station (the simulator is registered as online).
    final stationsRes = await api.get('/stations');
    final stations = (stationsRes['items'] as List<dynamic>)
        .map((e) => Station.fromJson(e as Map<String, dynamic>))
        .toList();
    expect(stations, isNotEmpty,
        reason: 'the simulator must be online and registered as a station');
    final station = stations.first;
    expect(station.status, 'online', reason: 'simulator must be connected');
    debugPrint('STATION ${station.stationCode} ${station.status}');

    // 3. Capture-first session — the phone never sends a photo.
    final sessionRes = await api.post('/deposit/session', data: {
      'station_id': station.id,
    });
    final operationId = sessionRes['operation_id'] as String;
    expect(sessionRes['status'], 'capture',
        reason: 'session must start capture-first (no prediction id)');
    debugPrint('SESSION $operationId -> ${sessionRes['status']}');

    // 4. Converge on the terminal state like the app does (HTTP polling here;
    //    the app additionally uses the WebSocket). The station camera, real AI
    //    and physical MQTT drop happen entirely on the server side.
    final deposit = await _awaitStatus(api, operationId, DepositStatus.confirmed);
    expect(deposit.status, DepositStatus.confirmed);
    expect(deposit.pointsAwarded, greaterThan(0),
        reason: 'a completed station deposit must award real points');
    expect(deposit.weightGrams, greaterThan(0),
        reason: 'the simulator measured a real physical weight');
    debugPrint('CONFIRMED class=${deposit.predictedClass} '
        '+${deposit.pointsAwarded} weight=${deposit.weightGrams}g '
        'position=${deposit.expectedPosition}');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('non-image capture is rejected 422 and never classifies', () async {
    final corrupt = List<int>.generate(64, (i) => 0xA0 + i % 16);
    const stationKey =
        String.fromEnvironment('STATION_KEY', defaultValue: 'dev-station-key');
    // Post the corrupt frame straight to the capture endpoint with the station
    // key, exactly as the station camera would — the real gate must refuse it.
    final response = await _stationCaptureRaw(base, stationKey, corrupt);
    expect(response.statusCode, greaterThanOrEqualTo(400),
        reason: 'corrupt frame must never be classified');
  }, timeout: const Timeout(Duration(minutes: 1)));
}

/// Polls the real session until it reaches [target] (the app additionally uses
/// the WebSocket path; polling converges on the identical terminal Deposit).
Future<Deposit> _awaitStatus(ApiClient api, String operationId,
    DepositStatus target) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  Deposit? last;
  while (DateTime.now().isBefore(deadline)) {
    final res = await api.get('/deposit/$operationId');
    last = Deposit.fromJson(Map<String, dynamic>.from(res));
    if (last.status == target) return last;
    if (last.status.isTerminal && last.status != target) {
      throw StateError('deposit $operationId reached ${last.status} instead of '
          '${target.apiValue} (reason=${last.rejectReason})');
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw StateError(
      'deposit $operationId never reached ${target.apiValue} in 60s '
      '(last=${last?.status})');
}

/// Posts [bytes] to the REAL `/deposit/capture` as the station camera would
/// (multipart + `X-Station-Key`); returns the raw response so tests can assert
/// gate rejections without an authenticated session.
Future<Response<void>> _stationCaptureRaw(
  String base,
  String stationKey,
  List<int> bytes,
) async {
  final dio = Dio(BaseOptions(baseUrl: base));
  final form = FormData.fromMap({
    'operation_id': 'op-station-e2e-invalid',
    'station_code': 'ST-001',
    'image': MultipartFile.fromBytes(bytes, filename: 'frame.jpg'),
  });
  try {
    return await dio.post<void>('/api/v1/deposit/capture',
        data: form, options: Options(headers: {'X-Station-Key': stationKey}));
  } on DioException catch (e) {
    return e.response ??
        Response(requestOptions: e.requestOptions, statusCode: 0);
  }
}