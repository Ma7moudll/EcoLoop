import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/shelf_multipart.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shared/shared.dart';

import 'ai.dart';
import 'auth.dart';
import 'config.dart';
import 'deposit.dart';
import 'json_file.dart';
import 'store.dart';

/// Builds the fully-wired HTTP handler (router + middleware) for the backend.
Handler buildHandler(ServerConfig config, DataStore store) {
  final auth = AuthService(store, secret: config.jwtSecret);
  final ai = AiService(config, store);
  final deposits = DepositService(config, store);

  final router = Router()
      ..mount('/api/v1', (Request request) => _apiRouter(auth, ai, deposits, store, config)(request))
      ..all('/<ignored|.*>', (Request request) =>
          jsonResponse(404, {'error': 'Not found.'}));

  return const Pipeline()
      .addMiddleware(_cors())
      .addMiddleware(_log())
      .addMiddleware(authMiddleware(auth))
      .addHandler((Request request) => router(request));
}

Router _apiRouter(
  AuthService auth,
  AiService ai,
  DepositService deposits,
  DataStore store,
  ServerConfig config,
) {
  final router = Router()
      ..get('/health', (Request r) =>
          jsonResponse(200, {'status': 'ok', 'demo': config.demoMode}))

      // ---- auth ----------------------------------------------------------
      ..post('/auth/register', (Request r) async {
        final body = await _jsonBody(r);
        if (body == null) return badRequest();
        final name = body['name'] as String? ?? '';
        final email = body['email'] as String? ?? '';
        final password = body['password'] as String? ?? '';
        final facultyId = body['faculty_id'] as String?;

        final error = auth.register(
          name: name,
          email: email,
          password: password,
          facultyId: facultyId,
        );
        if (error != null) return jsonResponse(400, {'error': error});
        final login = auth.login(email, password);
        if (login == null) return jsonResponse(400, {'error': 'Registration failed.'});
        return jsonResponse(201, {
          'token': login.token,
          'user': login.user.toJson(),
        });
      })
      ..post('/auth/login', (Request r) async {
        final body = await _jsonBody(r);
        if (body == null) return badRequest();
        final login = auth.login(
          body['email'] as String? ?? '',
          body['password'] as String? ?? '',
        );
        if (login == null) {
          return jsonResponse(401, {'error': 'Invalid email or password.'});
        }
        return jsonResponse(200, {'token': login.token, 'user': login.user.toJson()});
      })
      ..post('/auth/logout', guard((Request r, _) => Response(204)))
      ..get('/auth/me', guard((Request r, AppUser user) =>
          jsonResponse(200, {'user': user.toJson()})))

      // ---- ai ------------------------------------------------------------
      ..post('/ai/predict', guard((Request r, AppUser user) async {
        final form = r.formData();
        if (form == null) {
          return jsonResponse(415, {'error': 'Expected multipart/form-data.'});
        }
        List<int>? image;
        await for (final field in form.formData) {
          if (field.name == 'image') {
            image = await field.part.readBytes();
          }
        }
        if (image == null || image.isEmpty) {
          return jsonResponse(400, {'error': 'Missing image field.'});
        }
        try {
          final prediction = await ai.predict(image);
          await store.addPrediction(prediction);
          return jsonResponse(200, prediction.toJson());
        } on StateError catch (e) {
          return jsonResponse(422, {'error': e.message});
        } catch (_) {
          return jsonResponse(502, {'error': 'AI service unavailable.'});
        }
      }))

      // ---- deposit --------------------------------------------------------
      ..post('/deposit/session', guard((Request r, AppUser user) async {
        final body = await _jsonBody(r);
        if (body == null) return badRequest();
        final outcome = await deposits.createSession(
          predictionId: body['ai_prediction_id'] as String? ?? '',
          stationId: body['station_id'] as String? ?? Station.defaultStation.id,
          userId: user.id,
        );
        return switch (outcome) {
          DepositSuccess(deposit: final d) => jsonResponse(201, d.toJson()),
          DepositError(reason: final reason) => jsonResponse(422, {'error': reason}),
          DepositRejected() => jsonResponse(422, {'error': 'Deposit rejected.'}),
        };
      }))
      ..post('/deposit/confirm', guard((Request r, AppUser user) async {
        final body = await _jsonBody(r);
        if (body == null) return badRequest();
        final outcome = await deposits.confirm(
          userId: user.id,
          operationId: body['operation_id'] as String? ?? '',
          actualPosition: body['actual_position'] as int? ?? 0,
          weightGrams: (body['weight_g'] as num?)?.toDouble() ?? 0,
          mechanicalConfirmed: body['mechanical_confirmed'] as bool? ?? false,
        );
        return switch (outcome) {
          DepositSuccess(deposit: final d, :final challengeBonus) =>
            jsonResponse(200, {
              'deposit': d.toJson(),
              'points_awarded': d.pointsAwarded,
              'challenge_bonus': challengeBonus,
            }),
          DepositRejected(deposit: final d, reason: final reason) =>
            jsonResponse(200, {'deposit': d.toJson(), 'error': reason}),
          DepositError(reason: final reason) =>
            jsonResponse(409, {'error': reason}),
        };
      }))

      // ---- data ------------------------------------------------------------
      ..get('/users/me', guard((Request r, AppUser user) =>
          jsonResponse(200, {'user': store.userById(user.id)!.user.toJson()})))
      ..get('/waste/history', guard((Request r, AppUser user) {
        final rows = store.historyFor(user.id);
        return jsonResponse(200, {
          'items': rows.map((h) => h.event.toJson()).toList(),
        });
      }))
      ..get('/waste/history/<id>', (Request r, String id) async {
        final user = r.context['user'] as AppUser?;
        if (user == null) {
          return jsonResponse(401, {'error': 'Authentication required.'});
        }
        final row =
            store.historyFor(user.id).where((h) => h.event.id == id).firstOrNull;
        if (row == null) return jsonResponse(404, {'error': 'Event not found.'});
        return jsonResponse(200, {'item': row.event.toJson()});
      })
      ..get('/impact', guard((Request r, AppUser user) {
        final rows = store.historyFor(user.id);
        final record = store.userById(user.id)!;
        final kg = rows.fold<double>(0, (sum, h) => sum + h.event.weightGrams) / 1000;
        final breakdown = <WasteClass, ({double kg, int count})>{};
        for (final cls in WasteClass.values) {
          breakdown[cls] = (kg: 0, count: 0);
        }
        for (final h in rows) {
          final cur = breakdown[h.event.predictedClass]!;
          breakdown[h.event.predictedClass] =
              (kg: cur.kg + h.event.weightGrams / 1000, count: cur.count + 1);
        }
        final impact = Impact(
          totalPoints: record.user.points,
          recycledKg: round2(kg),
          itemsRecycled: rows.length,
          co2SavedKg: round2(kg * ConfigValues.co2PerKg),
          breakdown: WasteClass.values
              .map((cls) => WasteBreakdown(
                    wasteClass: cls,
                    kg: round2(breakdown[cls]!.kg),
                    count: breakdown[cls]!.count,
                  ))
              .toList(),
        );
        return jsonResponse(200, impact.toJson());
      }))
      ..get('/leaderboard', guard((Request r, AppUser user) {
        final scope = r.url.queryParameters['scope'] ?? 'students';
        final List<LeaderEntry> entries;
        if (scope == 'faculties') {
          entries = store.faculties
              .map((f) => LeaderEntry(
                    id: f.id,
                    name: f.name,
                    detail: 'Faculty',
                    points: store.facultyPoints(f.id),
                  ))
              .toList();
        } else {
          entries = store.users.values
              .map((u) => LeaderEntry(
                    id: u.user.id,
                    name: u.user.name,
                    detail: u.user.facultyName,
                    points: u.user.points,
                  ))
              .toList();
        }
        entries.sort((a, b) => b.points.compareTo(a.points));
        return jsonResponse(200, {
          'scope': scope,
          'entries': entries.map((e) => e.toJson()).toList(),
        });
      }))
      ..get('/challenges', guard((Request r, AppUser user) {
        final record = store.userById(user.id)!;
        final items =
            store.challenges.map((c) => store.challengeViewFor(c, record)).toList();
        return jsonResponse(200, {'items': items.map((e) => e.toJson()).toList()});
      }));

  return router;
}

class ConfigValues {
  static const double co2PerKg = 0.5;
}

// ---- helpers ---------------------------------------------------------------

FutureOr<Response> Function(Request) guard(
  FutureOr<Response> Function(Request, AppUser) inner,
) =>
    (Request request) async {
      final user = request.context['user'] as AppUser?;
      if (user == null) {
        return jsonResponse(401, {'error': 'Authentication required.'});
      }
      return inner(request, user);
    };

Middleware authMiddleware(AuthService auth) => (inner) => (request) async {
      final token = _bearer(request) ?? _cookieToken(request);
      if (token == null) return inner(request);
      final user = auth.userFromToken(token);
      if (user == null) return inner(request);
      return inner(request.change(context: {'user': user}));
    };

String? _bearer(Request request) {
  final header = request.headers['authorization'];
  if (header == null || !header.toLowerCase().startsWith('bearer ')) {
    return null;
  }
  return header.substring(7).trim();
}

String? _cookieToken(Request request) {
  final cookies = request.headers['cookie'];
  if (cookies == null) return null;
  final match = RegExp(r'ecoloop_session=([^;]+)').firstMatch(cookies);
  return match?.group(1);
}

Middleware _cors() => (inner) => (request) async {
      final headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Max-Age': '86400',
      };
      if (request.method == 'OPTIONS') return Response(204, headers: headers);
      final response = await inner(request);
      return response.change(headers: {...headers, ...response.headers});
    };

Middleware _log() => (inner) => (request) async {
      final sw = Stopwatch()..start();
      final response = await inner(request);
      sw.stop();
      print(
          '[${request.method}] ${request.url.path} → ${response.statusCode} (${sw.elapsedMilliseconds}ms)');
      return response;
    };

Future<Map<String, dynamic>?> _jsonBody(Request request) async {
  try {
    return jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

Response badRequest() => jsonResponse(400, {'error': 'Invalid JSON body.'});

Response jsonResponse(int status, Object body) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );