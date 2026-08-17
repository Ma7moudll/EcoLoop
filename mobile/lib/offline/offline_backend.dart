import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared/shared.dart';

import '../core/api_client.dart';
import '../core/app_config.dart';
import '../providers/providers.dart';
import '../services/ai_classifier.dart';
import '../services/auth_repository.dart';
import '../services/data_repository.dart';

/// Fully-local offline backend used when `--dart-define=OFFLINE_MODE=true`.
///
/// Every repository is replaced by an in-memory fake that mirrors the real
/// backend's shape so the app is navigable end-to-end without a server. The
/// isolated DEVICE-PREVIEW gating still holds: points are only ever produced
/// by a simulated deposit confirmation, never by scanning/mock data alone.
/// The subtle DEMO badge communicates that results are simulated.
class OfflineStore {
  AppUser user = const AppUser(
    id: 'u-demo',
    studentCode: 'S-DEMO',
    name: 'Demo Student',
    facultyId: 'engineering',
    facultyName: 'Faculty of Engineering',
    points: 45,
  );

  final Map<String, Prediction> predictions = {};
  final Map<String, Deposit> deposits = {};
  final List<WasteHistoryEvent> history = [];
  final List<LeaderEntry> studentLeaders = const [
    LeaderEntry(id: 'u-1', name: 'Hana Juma', detail: 'Medicine', points: 128),
    LeaderEntry(id: 'u-2', name: 'Omar Saeed', detail: 'Engineering', points: 96),
    LeaderEntry(id: 'u-demo', name: 'Demo Student', detail: 'Engineering', points: 45),
    LeaderEntry(id: 'u-3', name: 'Layla Noor', detail: 'Commerce', points: 34),
    LeaderEntry(id: 'u-4', name: 'Kareem Ali', detail: 'Science', points: 12),
  ];
  final List<LeaderEntry> facultyLeaders = const [
    LeaderEntry(id: 'engineering', name: 'Engineering', detail: 'Faculty', points: 17705),
    LeaderEntry(id: 'science', name: 'Science', detail: 'Faculty', points: 7910),
    LeaderEntry(id: 'commerce', name: 'Commerce', detail: 'Faculty', points: 6850),
    LeaderEntry(id: 'medicine', name: 'Medicine', detail: 'Faculty', points: 6120),
  ];
  final List<Challenge> challenges = [
    const Challenge(
      id: 'ch-1',
      title: 'Plastic Race',
      description: 'Recycle 2 kg of plastic',
      themeEmoji: '♻️',
      targetKg: 2.0,
      currentKg: 0.9,
      rewardPoints: 20,
      completed: false,
      active: true,
    ),
    const Challenge(
      id: 'ch-2',
      title: 'Paper Sprint',
      description: 'Recycle 1.5 kg of paper',
      themeEmoji: '📄',
      targetKg: 1.5,
      currentKg: 0.6,
      rewardPoints: 15,
      completed: false,
      active: true,
    ),
    const Challenge(
      id: 'ch-3',
      title: 'Metal Maker',
      description: 'Recycle 1 kg of metal',
      themeEmoji: '🥫',
      targetKg: 1.0,
      currentKg: 1.0,
      rewardPoints: 10,
      completed: true,
      active: false,
    ),
  ];

  OfflineStore() {
    history.addAll([
      WasteHistoryEvent(
        id: 'ev-1',
        operationId: 'OP-DEMO-1',
        stationId: 'st-001',
        predictedClass: WasteClass.plastic,
        weightGrams: 18.4,
        pointsAwarded: 5,
        createdAt: _at(daysAgo: 2),
      ),
      WasteHistoryEvent(
        id: 'ev-2',
        operationId: 'OP-DEMO-2',
        stationId: 'st-001',
        predictedClass: WasteClass.metal,
        weightGrams: 32.0,
        pointsAwarded: 10,
        createdAt: _at(daysAgo: 1),
      ),
      WasteHistoryEvent(
        id: 'ev-3',
        operationId: 'OP-DEMO-3',
        stationId: 'st-001',
        predictedClass: WasteClass.plastic,
        weightGrams: 21.5,
        pointsAwarded: 5,
        createdAt: _at(daysAgo: 0),
      ),
    ]);
  }

  static DateTime _at({required int daysAgo}) =>
      DateTime.now().toUtc().subtract(Duration(days: daysAgo, hours: 2));
}

/// Never touches the platform keychain — offline storage is a no-op.
class _MemoryStorage extends FlutterSecureStorage {
  const _MemoryStorage();

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      null;

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {}

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {}
}

/// Mock AI that registers its predictions with the local store so the deposit
/// flow can resolve them. Otherwise identical to the offline [MockAiClassifier].
class OfflineAiClassifier extends MockAiClassifier {
  final OfflineStore _store;
  OfflineAiClassifier(this._store);

  @override
  Future<Prediction> predictImage(List<int> jpegBytes) async {
    final prediction = await super.predictImage(jpegBytes);
    _store.predictions[prediction.predictionId] = prediction;
    return prediction;
  }
}

/// Pre-signed-in auth: any credentials log in as the demo student.
class OfflineAuthRepository extends AuthRepository {
  final OfflineStore _store;

  OfflineAuthRepository(this._store)
      : super(ApiClient('http://localhost:8080/api/v1'), const _MemoryStorage());

  @override
  Future<String?> restoreToken() async => 'offline-token';

  @override
  Future<void> persistToken(String token) async {}

  @override
  Future<void> clearSession() async {}

  @override
  Future<AppUser> fetchMe() async => _store.user;

  @override
  Future<(String, AppUser)> login(String email, String password) async =>
      ('offline-token', _store.user);

  @override
  Future<(String, AppUser)> register({
    required String name,
    required String email,
    required String password,
  }) async =>
      ('offline-token', _store.user);
}

/// Reads impact / history / leaderboard / challenges from the local store.
class OfflineDataRepository extends DataRepository {
  final OfflineStore _store;

  OfflineDataRepository(this._store)
      : super(ApiClient('http://localhost:8080/api/v1'));

  @override
  Future<AppUser> fetchMe() async => _store.user;

  @override
  Future<Impact> fetchImpact() async {
    final kgByClass = <WasteClass, double>{};
    final countByClass = <WasteClass, int>{};
    for (final cls in WasteClass.values) {
      kgByClass[cls] = 0;
      countByClass[cls] = 0;
    }
    for (final h in _store.history) {
      kgByClass[h.predictedClass] = kgByClass[h.predictedClass]! + h.weightGrams / 1000;
      countByClass[h.predictedClass] = countByClass[h.predictedClass]! + 1;
    }
    final totalKg = kgByClass.values.fold<double>(0, (a, b) => a + b);
    return Impact(
      totalPoints: _store.user.points,
      recycledKg: _round(totalKg),
      itemsRecycled: _store.history.length,
      co2SavedKg: _round(totalKg * 0.5),
      breakdown: [
        for (final cls in WasteClass.values)
          WasteBreakdown(
            wasteClass: cls,
            kg: _round(kgByClass[cls]!),
            count: countByClass[cls]!,
          ),
      ],
    );
  }

  @override
  Future<List<WasteHistoryEvent>> fetchHistory() async =>
      List.unmodifiable(_store.history.reversed);

  @override
  Future<List<Challenge>> fetchChallenges() async =>
      List.unmodifiable(_store.challenges);

  @override
  Future<List<LeaderEntry>> fetchLeaderboard(
      {LeaderScope scope = LeaderScope.students}) async {
    final entries = scope == LeaderScope.students
        ? _store.studentLeaders
        : _store.facultyLeaders;
    final sorted = [...entries]..sort((a, b) => b.points.compareTo(a.points));
    return sorted;
  }
}

/// Simulated station: creates sessions and validates confirmations, awarding
/// points ONLY after a passing simulated deposit (mirrors the real gates:
/// compartment match, minimum weight, mechanical confirmation).
class OfflineDepositRepository extends DepositRepository {
  final OfflineStore _store;

  OfflineDepositRepository(this._store)
      : super(ApiClient('http://localhost:8080/api/v1'));

  @override
  Future<Deposit> createSession(
      {required String predictionId, required String stationId}) async {
    final prediction = _store.predictions[predictionId];
    final deposit = Deposit(
      operationId: 'OP-LIVE-${DateTime.now().millisecondsSinceEpoch % 99999}',
      predictionId: predictionId,
      stationId: Station.defaultStation.id,
      predictedClass: prediction?.predictedClass ?? WasteClass.plastic,
      expectedPosition:
          prediction?.destinationPosition ?? positionForClass(WasteClass.plastic),
      actualPosition: 0,
      weightGrams: 0,
      mechanicalConfirmed: false,
      potentialPoints: prediction?.potentialPoints ?? 5,
      pointsAwarded: 0,
      status: DepositStatus.pending,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
    );
    _store.deposits[deposit.operationId] = deposit;
    return deposit;
  }

  @override
  Future<({Deposit deposit, int pointsAwarded, int challengeBonus})> awaitDeposit(
    Deposit session, {
    Duration pollInterval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final deposit = _store.deposits[session.operationId]!;
    return _simulateDrop(deposit);
  }

  /// Simulated station drop, mirroring the real validation gates
  /// (compartment match, minimum weight, mechanical confirmation).
  Future<({Deposit deposit, int pointsAwarded, int challengeBonus})> _simulateDrop(
      Deposit deposit) async {
    final actualPosition = deposit.expectedPosition;
    final weightGrams = AppConfig.simulatedWeightGrams;
    final mechanicalConfirmed = true;

    if (actualPosition != deposit.expectedPosition ||
        weightGrams < 1.0 ||
        !mechanicalConfirmed) {
      final rejected = Deposit(
        operationId: deposit.operationId,
        predictionId: deposit.predictionId,
        stationId: deposit.stationId,
        predictedClass: deposit.predictedClass,
        expectedPosition: deposit.expectedPosition,
        actualPosition: actualPosition,
        weightGrams: weightGrams,
        mechanicalConfirmed: mechanicalConfirmed,
        potentialPoints: deposit.potentialPoints,
        pointsAwarded: 0,
        status: DepositStatus.rejected,
        expiresAt: deposit.expiresAt,
        rejectReason: 'Simulated rejection: wrong compartment or low weight.',
      );
      _store.deposits[deposit.operationId] = rejected;
      return (
        deposit: rejected,
        pointsAwarded: 0,
        challengeBonus: 0,
      );
    }

    final confirmed = Deposit(
      operationId: deposit.operationId,
      predictionId: deposit.predictionId,
      stationId: deposit.stationId,
      predictedClass: deposit.predictedClass,
      expectedPosition: deposit.expectedPosition,
      actualPosition: actualPosition,
      weightGrams: weightGrams,
      mechanicalConfirmed: true,
      potentialPoints: deposit.potentialPoints,
      pointsAwarded: deposit.potentialPoints,
      status: DepositStatus.confirmed,
      expiresAt: deposit.expiresAt,
    );
    _store.deposits[deposit.operationId] = confirmed;
    _store.user = _store.user.copyWith(
      points: _store.user.points + confirmed.pointsAwarded,
    );
    _store.history.add(WasteHistoryEvent(
      id: 'ev-${DateTime.now().millisecondsSinceEpoch}',
      operationId: confirmed.operationId,
      stationId: confirmed.stationId,
      predictedClass: confirmed.predictedClass,
      weightGrams: confirmed.weightGrams,
      pointsAwarded: confirmed.pointsAwarded,
      createdAt: DateTime.now().toUtc(),
    ));
    return (
      deposit: confirmed,
      pointsAwarded: confirmed.pointsAwarded,
      challengeBonus: 0,
    );
  }
}

double _round(double v) => (v * 100).round() / 100;

/// Overrides that make the whole app local. One shared [OfflineStore] keeps
/// auth, AI, data and deposits consistent with each other.
List<Override> offlineOverrides() {
  final store = OfflineStore();
  return [
    aiClassifierProvider.overrideWithValue(OfflineAiClassifier(store)),
    authRepositoryProvider.overrideWithValue(OfflineAuthRepository(store)),
    dataRepositoryProvider.overrideWithValue(OfflineDataRepository(store)),
    depositRepositoryProvider.overrideWithValue(OfflineDepositRepository(store)),
  ];
}