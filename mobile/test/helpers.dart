import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:recycle_vision/core/api_client.dart';
import 'package:recycle_vision/services/auth_repository.dart';
import 'package:recycle_vision/services/data_repository.dart';
import 'package:recycle_vision/services/deposit_status_channel.dart';
import 'package:shared/shared.dart';

/// No-op secure storage so auth fakes never touch platform channels.
class _NoopStorage extends FlutterSecureStorage {
  const _NoopStorage();

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

/// Fake auth that never touches secure storage or the network.
class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository() : super(ApiClient('http://localhost:9999'), const _NoopStorage());

  @override
  Future<String?> restoreToken() async => null;

  @override
  Future<void> persistToken(String token) async {}

  @override
  Future<void> clearSession() async {}

  @override
  Future<(String, AppUser)> login(String email, String password) async =>
      ('tok', fakeUser());

  @override
  Future<AppUser> register({
    required String name,
    required String email,
    required String facultyId,
    required String password,
    required String studentCode,
  }) async =>
      fakeUser();

  @override
  Future<AppUser> fetchMe() async => fakeUser();
}

/// Test doubles + fixtures shared across widget tests. Providers are overridden
/// so no real network or platform channels are touched.

AppUser fakeUser({int points = 45}) => AppUser(
      id: 'u-test',
      studentCode: 'S-001',
      name: 'Test Student',
      facultyId: 'engineering',
      facultyName: 'Faculty of Engineering',
      points: points,
    );

Prediction fakePrediction({WasteClass cls = WasteClass.plastic}) {
  final compartment = compartmentForClass(cls);
  return Prediction(
    predictionId: 'pred-test',
    operationId: 'OP-TEST',
    predictedClass: cls,
    confidence: 0.97,
    confidenceLevel: ConfidenceLevel.high,
    recyclable: cls.isRecyclable,
    destinationPosition: compartment.position,
    potentialPoints: compartment.potentialPoints,
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    source: 'demo',
  );
}

Deposit fakeSession() => Deposit(
      operationId: 'OP-TEST',
      predictionId: 'pred-test',
      stationId: Station.defaultStation.id,
      predictedClass: WasteClass.plastic,
      expectedPosition: 1,
      actualPosition: 0,
      weightGrams: 0,
      mechanicalConfirmed: false,
      potentialPoints: 5,
      pointsAwarded: 0,
      status: DepositStatus.pending,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );

Deposit fakeConfirmedDeposit({int awarded = 5}) => Deposit(
      operationId: 'OP-TEST',
      predictionId: 'pred-test',
      stationId: Station.defaultStation.id,
      predictedClass: WasteClass.plastic,
      expectedPosition: 1,
      actualPosition: 1,
      weightGrams: 18.4,
      mechanicalConfirmed: true,
      potentialPoints: 5,
      pointsAwarded: awarded,
      status: DepositStatus.confirmed,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );

/// A deposit in any state (live phase or terminal) for status tests.
Deposit fakeDeposit(
  DepositStatus status, {
  int actualPosition = 0,
  double weightGrams = 0,
  bool mechanicalConfirmed = false,
  int pointsAwarded = 0,
  String? rejectReason,
}) =>
    Deposit(
      operationId: 'OP-TEST',
      predictionId: 'pred-test',
      stationId: Station.defaultStation.id,
      predictedClass: WasteClass.plastic,
      expectedPosition: 1,
      actualPosition: actualPosition,
      weightGrams: weightGrams,
      mechanicalConfirmed: mechanicalConfirmed,
      potentialPoints: 5,
      pointsAwarded: pointsAwarded,
      status: status,
      rejectReason: rejectReason,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );

class FakeDataRepository extends DataRepository {
  FakeDataRepository() : super(ApiClient('http://localhost:9999'));

  AppUser? user;
  List<Station> stations = const [Station.defaultStation];

  @override
  Future<AppUser> fetchMe() async => user ?? fakeUser();

  @override
  Future<List<Station>> fetchStations() async => stations;

  @override
  Future<Impact> fetchImpact() async => Impact(
        totalPoints: 45,
        recycledKg: 0.6,
        itemsRecycled: 3,
        co2SavedKg: 0.3,
        breakdown: const [
          WasteBreakdown(wasteClass: WasteClass.plastic, kg: 0.4, count: 2),
          WasteBreakdown(wasteClass: WasteClass.metal, kg: 0.2, count: 1),
          WasteBreakdown(wasteClass: WasteClass.paper, kg: 0.0, count: 0),
          WasteBreakdown(wasteClass: WasteClass.other, kg: 0.0, count: 0),
        ],
      );

  @override
  Future<List<WasteHistoryEvent>> fetchHistory() async => [
        WasteHistoryEvent(
          id: 'ev-1',
          operationId: 'OP-TEST',
          stationId: Station.defaultStation.id,
          predictedClass: WasteClass.plastic,
          weightGrams: 18.4,
          pointsAwarded: 5,
          createdAt: DateTime.now().toUtc(),
        ),
      ];

  @override
  Future<List<Challenge>> fetchChallenges() async => const [
        Challenge(
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
      ];
}

class FakeDepositRepository extends DepositRepository {
  FakeDepositRepository() : super(ApiClient('http://localhost:9999'));

  Deposit session = fakeSession();
  Deposit outcome = fakeConfirmedDeposit();

  @override
  Future<Deposit> createSession(
      {String? predictionId, required String stationId}) async {
    return session;
  }

  @override
  Future<({Deposit deposit, int pointsAwarded, int challengeBonus})> awaitDeposit(
    Deposit session, {
    Duration pollInterval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 3),
  }) async {
    return (
      deposit: outcome,
      pointsAwarded: outcome.pointsAwarded,
      challengeBonus: 0,
    );
  }
}

/// Realtime channel fake: replays a script of live phases (with a small
/// per-phase delay so the UI can render them) before returning a terminal
/// outcome — exactly like the real WebSocket, without any socket.
class FakeDepositStatusChannel extends DepositStatusChannel {
  FakeDepositStatusChannel()
      : super(ApiClient('http://localhost:9999')..setToken('tok'),
            FakeDepositRepository());

  final List<Deposit> live = [];
  ({Deposit deposit, int pointsAwarded, int challengeBonus}) outcome =
      (deposit: fakeConfirmedDeposit(), pointsAwarded: 5, challengeBonus: 0);
  Duration phaseDelay = const Duration(milliseconds: 40);

  @override
  Future<({Deposit deposit, int pointsAwarded, int challengeBonus})>
      awaitDeposit(
    Deposit session, {
    void Function(Deposit live)? onLive,
    Duration pollInterval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 3),
  }) async {
    for (final phase in live) {
      onLive?.call(phase);
      await Future<void>.delayed(phaseDelay);
    }
    return outcome;
  }
}