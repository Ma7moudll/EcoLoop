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

/// Deposit session + confirm operations.
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

  /// Returns the confirm response. Points are ONLY ever present when the
  /// backend accepted the deposit.
  Future<({Deposit deposit, int pointsAwarded, int challengeBonus})> confirm({
    required String operationId,
    required int actualPosition,
    required double weightGrams,
    required bool mechanicalConfirmed,
  }) async {
    final body = await _api.post('/deposit/confirm', data: {
      'operation_id': operationId,
      'actual_position': actualPosition,
      'weight_g': weightGrams,
      'mechanical_confirmed': mechanicalConfirmed,
    });
    return (
      deposit: Deposit.fromJson(body['deposit'] as Map<String, dynamic>),
      pointsAwarded: (body['points_awarded'] as num?)?.toInt() ?? 0,
      challengeBonus: (body['challenge_bonus'] as num?)?.toInt() ?? 0,
    );
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