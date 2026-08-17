import 'package:shared/shared.dart';

import '../core/api_client.dart';

/// Typed data services for everything that previously used static constants:
/// points, impact, history, leaderboard, challenges. After a confirmed deposit
/// the UI invalidates the related Riverpod providers so the new points appear
/// immediately (spec §17).
class DataRepository {
  final ApiClient _api;

  DataRepository(this._api);

  Future<AppUser> fetchMe() async {
    final body = await _api.get('/users/me');
    return AppUser.fromJson(body['user'] as Map<String, dynamic>);
  }

  Future<Impact> fetchImpact() async {
    return Impact.fromJson(await _api.get('/impact'));
  }

  Future<List<WasteHistoryEvent>> fetchHistory() async {
    final body = await _api.get('/waste/history');
    return (body['items'] as List<dynamic>)
        .map((e) => WasteHistoryEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<WasteHistoryEvent> fetchHistoryEvent(String id) async {
    final body = await _api.get('/waste/history/$id');
    return WasteHistoryEvent.fromJson(body['item'] as Map<String, dynamic>);
  }

  Future<List<Challenge>> fetchChallenges() async {
    final body = await _api.get('/challenges');
    return (body['items'] as List<dynamic>)
        .map((e) => Challenge.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<LeaderEntry>> fetchLeaderboard(
      {LeaderScope scope = LeaderScope.students}) async {
    final body =
        await _api.get('/leaderboard', query: {'scope': scope.apiValue});
    return (body['entries'] as List<dynamic>)
        .map((e) => LeaderEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

enum LeaderScope {
  students('students'),
  faculties('faculties');

  final String apiValue;
  const LeaderScope(this.apiValue);
}

/// Deposit session + live status. Points are ONLY ever awarded server-side
/// after a physical MQTT sensor event; the client polls [awaitDeposit] until
/// the station (or, in offline preview, its simulation) reaches a terminal
/// state. There is deliberately no HTTP confirm shortcut — the backend has no
/// such route, and points can never come from the client.
class DepositRepository {
  final ApiClient _api;

  DepositRepository(this._api);

  Future<Deposit> createSession(
      {required String predictionId,
      required String stationId}) async {
    final body = await _api.post('/deposit/session', data: {
      'ai_prediction_id': predictionId,
      'station_id': stationId,
    });
    return Deposit.fromJson(body);
  }

  Future<Deposit> fetchDeposit(String operationId) async {
    final body = await _api.get('/deposit/$operationId');
    return Deposit.fromJson(body);
  }

  Future<void> cancelSession(String operationId) async {
    await _api.post('/deposit/$operationId/cancel');
  }

  /// Waits for the deposit to reach a terminal state. In online mode this
  /// polls the real backend until the physical station finishes the drop; in
  /// offline preview the simulated station resolves immediately. Points come
  /// only from the returned deposit — never fabricated here.
  Future<({Deposit deposit, int pointsAwarded, int challengeBonus})> awaitDeposit(
    Deposit session, {
    Duration pollInterval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var current = session;
    while (DateTime.now().isBefore(deadline)) {
      current = await fetchDeposit(session.operationId);
      if (current.status.isTerminal) {
        return (
          deposit: current,
          pointsAwarded: current.pointsAwarded,
          challengeBonus: 0,
        );
      }
      await Future<void>.delayed(pollInterval);
    }
    throw ApiException('The station did not respond in time. Please retry.');
  }
}

/// Validates credentials/forms on the client before hitting the backend.
abstract final class Validation {
  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? validateName(String name) =>
      name.trim().isEmpty ? 'Name is required.' : null;

  static String? validateEmail(String email) =>
      !_emailRe.hasMatch(email.trim()) ? 'Enter a valid email address.' : null;

  static String? validatePassword(String password) =>
      password.length < 6 ? 'Password must be at least 6 characters.' : null;
}