import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:server/auth.dart';
import 'package:server/config.dart';
import 'package:server/deposit.dart';
import 'package:server/seed.dart';
import 'package:server/server.dart';
import 'package:server/store.dart';
import 'package:shelf/shelf.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// Builds a fully-wired test harness backed by a temp data directory.
class TestApi {
  final Directory dir;
  final DataStore store;
  final Handler handler;

  TestApi._(this.dir, this.store, this.handler);

  static Future<TestApi> create() async {
    final dir = await Directory.systemTemp.createTemp('recycle_vision_test_');
    pbkdf2Iterations = 1000;
    final config = ServerConfig(
      port: 0,
      dataDir: dir.path,
      demoMode: true,
      aiApiUrl: null,
      aiApiKey: null,
      jwtSecret: 'test-secret-0123456789',
      predictionLifetime: const Duration(minutes: 5),
      depositLifetime: const Duration(minutes: 5),
    );
    final store = await DataStore.create(dir.path);
    if (!store.isSeeded) await seedStore(store);
    store.setConfig(config);
    return TestApi._(dir, store, buildHandler(config, store));
  }

  Future<(int, Map<String, dynamic>)> call(
    String method,
    String path, {
    Map<String, dynamic>? json,
    String? token,
    List<int>? imageBytes,
  }) async {
    final headers = <String, String>{
      'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
    };
    Object? body;
    if (json != null) body = jsonEncode(json);
    if (imageBytes != null) {
      headers['content-type'] =
          'multipart/form-data; boundary=----rvTestBoundary';
      body = Uint8List.fromList(_multipartBody(imageBytes));
    }
    final request = Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: headers,
      body: body,
    );
    final response = await handler(request);
    final text = await response.readAsString();
    final decoded = text.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(text) as Map<String, dynamic>;
    return (response.statusCode, decoded);
  }

  Future<String> registerAndLogin(String email) async {
    final (code, body) = await call('POST', '/api/v1/auth/register', json: {
      'name': 'Test User',
      'email': email,
      'password': 'secret123',
    });
    expect(code, 201, reason: body.toString());
    return body['token'] as String;
  }

  /// The demo AI produces low-confidence outcomes ~10% of the time (randomized
  /// per image bytes), so retry with fresh bytes until a depositable
  /// (high/medium) prediction is returned.
  Future<Prediction> predictDepositable(String authToken) async {
    final rand = Random();
    for (var attempt = 0; attempt < 30; attempt++) {
      final image = Uint8List.fromList(
          List<int>.generate(1024 + rand.nextInt(4096), (_) => rand.nextInt(256)));
      final (code, body) = await call(
          'POST', '/api/v1/ai/predict',
          token: authToken, imageBytes: image);
      expect(code, 200, reason: body.toString());
      final p = Prediction.fromJson(body);
      if (p.confidenceLevel != ConfidenceLevel.low) return p;
    }
    fail('Could not produce a depositable prediction after 30 attempts.');
  }

  List<int> _multipartBody(List<int> content) {
    const boundary = '------rvTestBoundary';
    final header = utf8.encode(
      '$boundary\r\n'
      'Content-Disposition: form-data; name="image"; filename="capture.jpg"\r\n'
      'Content-Type: image/jpeg\r\n\r\n',
    );
    final footer = utf8.encode('\r\n$boundary--\r\n');
    return [...header, ...content, ...footer];
  }

  Future<void> dispose() async {
    await store.saveAll();
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}

void main() {
  group('AuthService', () {
    test('PBKDF2-SHA256 matches RFC 2898 test vector', () {
      final hash = pbkdf2Sha256(
        password: utf8.encode('password'),
        salt: utf8.encode('salt'),
        iterations: 1,
      );
      expect(
        hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
    });

    test('same password + different salt produce different hashes', () {
      expect(pbkdf2Hash('pw', 'salt-a'), isNot(pbkdf2Hash('pw', 'salt-b')));
    });

    test('JWT rejects a tampered signature', () {
      final jwt = Jwt('secret');
      final token = jwt.sign(subject: 'u1');
      final wrong = Jwt('other-secret');
      expect(wrong.verify(token), isNull);
      expect(jwt.verify(token), 'u1');
    });

    test('JWT rejects an expired token', () async {
      final jwt = Jwt('secret');
      final token = jwt.sign(subject: 'u1', lifetime: const Duration(milliseconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(jwt.verify(token), isNull);
    });
  });

  group('DepositService validation', () {
    late DataStore store;
    late DepositService service;

    setUp(() async {
      pbkdf2Iterations = 1000;
      final dir = await Directory.systemTemp.createTemp('rv_deposit_test_');
      store = DataStore(dir.path);
      final config = ServerConfig(
        port: 0,
        dataDir: dir.path,
        demoMode: true,
        aiApiUrl: null,
        aiApiKey: null,
        jwtSecret: 's',
        predictionLifetime: const Duration(minutes: 5),
        depositLifetime: const Duration(minutes: 5),
      );
      service = DepositService(config, store);
    });

    Prediction prediction({
      WasteClass cls = WasteClass.plastic,
      double confidence = 0.96,
      DateTime? expiresAt,
    }) =>
        Prediction(
          predictionId: 'pred_1',
          operationId: 'OP-11111',
          predictedClass: cls,
          confidence: confidence,
          confidenceLevel: confidenceLevelFor(confidence),
          recyclable: cls.isRecyclable,
          destinationPosition: positionForClass(cls),
          potentialPoints: compartmentForClass(cls).potentialPoints,
          expiresAt: expiresAt ?? DateTime.now().toUtc().add(const Duration(minutes: 5)),
          source: 'demo',
        );

    test('high confidence creates a session with matching position', () async {
      store.predictions['pred_1'] = prediction();
      final outcome = await service.createSession(
          predictionId: 'pred_1', stationId: 'st-001', userId: 'u1');
      expect(outcome, isA<DepositSuccess>());
      final deposit = (outcome as DepositSuccess).deposit;
      expect(deposit.status, DepositStatus.pending);
      expect(deposit.expectedPosition, 1);
      expect(deposit.potentialPoints, 5);
      expect(deposit.expiresAt.isAfter(DateTime.now().toUtc()), isTrue);
    });

    test('low confidence cannot create a session', () async {
      store.predictions['pred_1'] = prediction(confidence: 0.41);
      final outcome = await service.createSession(
          predictionId: 'pred_1', stationId: 'st-001', userId: 'u1');
      expect(outcome, isA<DepositError>());
    });

    test('a prediction can only be used once', () async {
      store.predictions['pred_1'] = prediction();
      await service.createSession(predictionId: 'pred_1', stationId: 'st-001', userId: 'u1');
      final second = await service.createSession(
          predictionId: 'pred_1', stationId: 'st-001', userId: 'u1');
      expect(second, isA<DepositError>());
    });

    test('expired prediction cannot create a session', () async {
      store.predictions['pred_1'] =
          prediction(expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)));
      final outcome = await service.createSession(
          predictionId: 'pred_1', stationId: 'st-001', userId: 'u1');
      expect(outcome, isA<DepositError>());
    });
  });

  group('Full API flow (authoritative points)', () {
    late TestApi api;
    late String token;

    setUpAll(() async {
      api = await TestApi.create();
      token = await api.registerAndLogin('new@recycle.vision');
    });

    tearDownAll(() => api.dispose());

    test('register + login + me identify the same real user', () async {
      final (code, body) = await api.call(
          'GET', '/api/v1/auth/me',
          token: token);
      expect(code, 200);
      expect(((body['user'] as Map<String, dynamic>))['name'], 'Test User');
      expect(((body['user'] as Map<String, dynamic>))['points'], 0);
    });

    test('unauthenticated requests are rejected', () async {
      final (code, _) = await api.call('GET', '/api/v1/impact');
      expect(code, 401);
    });

    test('invalid password is rejected', () async {
      final (code, _) = await api.call('POST', '/api/v1/auth/login', json: {
        'email': 'new@recycle.vision',
        'password': 'wrong-pass',
      });
      expect(code, 401);
    });

    test('full vertical: predict -> session -> confirm awards points once', () async {
      // 1. predict (retry until depositable)
      final prediction = await api.predictDepositable(token);

      // 2. create session
      final (sCode, sBody) = await api.call(
          'POST', '/api/v1/deposit/session',
          token: token,
          json: {'ai_prediction_id': prediction.predictionId});
      expect(sCode, 201, reason: sBody.toString());
      final session = Deposit.fromJson(sBody);
      expect(session.status, DepositStatus.pending);

      // 3. confirm with all gates passing
      final (cCode, cBody) = await api.call(
          'POST', '/api/v1/deposit/confirm',
          token: token,
          json: {
            'operation_id': session.operationId,
            'actual_position': session.expectedPosition,
            'weight_g': 18.4,
            'mechanical_confirmed': true,
          });
      expect(cCode, 200, reason: cBody.toString());
      final confirmed = Deposit.fromJson(cBody['deposit'] as Map<String, dynamic>);
      expect(confirmed.status, DepositStatus.confirmed);
      expect(cBody['points_awarded'], session.potentialPoints);

      // 4. replay is rejected and can NEVER award points twice
      final (rCode, rBody) = await api.call(
          'POST', '/api/v1/deposit/confirm',
          token: token,
          json: {
            'operation_id': session.operationId,
            'actual_position': session.expectedPosition,
            'weight_g': 18.4,
            'mechanical_confirmed': true,
          });
      expect(rCode, 409, reason: rBody.toString());

      // 5. points are visible in /users/me and impact
      final (mCode, mBody) = await api.call('GET', '/api/v1/users/me', token: token);
      expect(mCode, 200);
      final me = AppUser.fromJson(mBody['user'] as Map<String, dynamic>);
      expect(me.points, session.potentialPoints);

      final (iCode, iBody) = await api.call('GET', '/api/v1/impact', token: token);
      expect(iCode, 200);
      final impact = Impact.fromJson(iBody);
      expect(impact.itemsRecycled, 1);
      expect(impact.recycledKg, closeTo(0.02, 0.001)); // 18.4 g rounded

      // 6. history contains the event
      final (hCode, hBody) = await api.call('GET', '/api/v1/waste/history', token: token);
      expect(hCode, 200);
      final items = (hBody['items'] as List).cast<Map>();
      expect(items, hasLength(1));
    });

    test('wrong compartment rejects the deposit and awards nothing', () async {
      final prediction = await api.predictDepositable(token);

      final (sCode, sBody) = await api.call(
          'POST', '/api/v1/deposit/session',
          token: token,
          json: {'ai_prediction_id': prediction.predictionId});
      expect(sCode, 201);
      final session = Deposit.fromJson(sBody);

      final wrongPosition = session.expectedPosition == 4 ? 1 : session.expectedPosition + 1;
      final (cCode, cBody) = await api.call(
          'POST', '/api/v1/deposit/confirm',
          token: token,
          json: {
            'operation_id': session.operationId,
            'actual_position': wrongPosition,
            'weight_g': 30,
            'mechanical_confirmed': true,
          });
      expect(cCode, 200, reason: cBody.toString());
      final dep = Deposit.fromJson(cBody['deposit'] as Map<String, dynamic>);
      expect(dep.status, DepositStatus.rejected);
      expect(dep.pointsAwarded, 0);

      final (mCode, mBody) = await api.call('GET', '/api/v1/users/me', token: token);
      final me = AppUser.fromJson(mBody['user'] as Map<String, dynamic>);
      // Nothing was awarded — points stay at 0 for this fresh user.
      expect(me.points, 0);
    });
  });

  group('Leaderboard & challenges', () {
    late TestApi api;
    late String token;

    setUpAll(() async {
      api = await TestApi.create();
      token = await api.registerAndLogin('board@recycle.vision');
    });

    tearDownAll(() => api.dispose());

    test('seeded demo leaderboard is returned and sorted desc', () async {
      final (code, body) = await api.call('GET', '/api/v1/leaderboard', token: token);
      expect(code, 200);
      final entries = (body['entries'] as List).cast<Map>();
      expect(entries, isNotEmpty);
      var prev = 1 << 30;
      for (final e in entries) {
        final pts = e['points'] as int;
        expect(pts <= prev, isTrue);
        prev = pts;
      }
      expect(entries.any((e) => e['name'] == 'Maya Chen'), isTrue);
    });

    test('faculties scope aggregates by faculty', () async {
      final (code, body) = await api.call(
          'GET', '/api/v1/leaderboard?scope=faculties', token: token);
      expect(code, 200);
      final entries = (body['entries'] as List).cast<Map>();
      expect(entries.any((e) => e['detail'] == 'Faculty'), isTrue);
      // Engineering should lead per seed totals
      expect(entries.first['name'], 'Engineering');
    });

    test('challenges are returned with live progress', () async {
      final (code, body) = await api.call('GET', '/api/v1/challenges', token: token);
      expect(code, 200);
      final items = (body['items'] as List).cast<Map>();
      expect(items, isNotEmpty);
      expect(items.every((c) => c['reward_points'] is int), isTrue);
    });
  });
}