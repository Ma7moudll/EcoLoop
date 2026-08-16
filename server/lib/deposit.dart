import 'package:shared/shared.dart';

import 'config.dart';
import 'json_file.dart';
import 'store.dart';

/// Minimum weight for a deposit to count (grams). Below this the load cell is
/// considered to have detected nothing real.
const double minDepositWeightGrams = 1.0;

/// Outcome of a deposit confirmation. Only [success] carries awarded points;
/// every other path explains *why* no points were given.
sealed class DepositOutcome {
  const DepositOutcome();
}

class DepositSuccess extends DepositOutcome {
  final Deposit deposit;
  final int pointsAwarded;
  final int challengeBonus;
  const DepositSuccess(this.deposit, this.pointsAwarded, {this.challengeBonus = 0});

  int get totalAwarded => pointsAwarded + challengeBonus;
}

class DepositRejected extends DepositOutcome {
  final Deposit deposit;
  final String reason;
  const DepositRejected(this.deposit, this.reason);
}

class DepositError extends DepositOutcome {
  final String reason;
  const DepositError(this.reason);
}

/// A single operation ID can only ever produce one outcome. [DepositService]
/// is the ONLY place in the codebase that awards points.
class DepositService {
  final ServerConfig config;
  final DataStore store;

  DepositService(this.config, this.store);

  /// Creates a pending deposit session for a prediction. Returns
  /// [DepositError] when the prediction is invalid, expired, low-confidence
  /// or already consumed — the server refuses to mint a second operation
  /// from the same prediction (replay protection).
  Future<DepositOutcome> createSession({
    required String predictionId,
    required String stationId,
    required String userId,
  }) async {
    final prediction = store.predictions[predictionId];
    if (prediction == null) {
      return const DepositError('Unknown prediction.');
    }
    if (store.depositByPrediction.containsKey(predictionId)) {
      return const DepositError('This prediction was already used.');
    }
    if (prediction.expiresAt.isBefore(DateTime.now().toUtc())) {
      return const DepositError('This prediction has expired. Scan again.');
    }
    if (prediction.confidenceLevel == ConfidenceLevel.low) {
      return const DepositError('Low-confidence prediction cannot be deposited.');
    }

    if (stationId != Station.defaultStation.id) {
      return const DepositError('Unknown station.');
    }

    final deposit = Deposit(
      operationId: prediction.operationId,
      predictionId: prediction.predictionId,
      stationId: Station.defaultStation.id,
      predictedClass: prediction.predictedClass,
      expectedPosition: prediction.destinationPosition,
      actualPosition: 0,
      weightGrams: 0,
      mechanicalConfirmed: false,
      potentialPoints: prediction.potentialPoints,
      pointsAwarded: 0,
      status: DepositStatus.pending,
      expiresAt: DateTime.now().toUtc().add(config.depositLifetime),
    );
    await store.addDeposit(deposit);
    return DepositSuccess(deposit, deposit.potentialPoints);
  }

  /// Confirms (or rejects) a deposit session. Points are only ever awarded
  /// here, AND only when every gate passes. A rejected or replayed operation
  /// can never award points twice.
  Future<DepositOutcome> confirm({
    required String userId,
    required String operationId,
    required int actualPosition,
    required double weightGrams,
    required bool mechanicalConfirmed,
  }) async {
    final deposit = store.deposits[operationId];
    if (deposit == null) {
      return const DepositError('Unknown operation.');
    }
    if (deposit.status == DepositStatus.confirmed ||
        deposit.status == DepositStatus.rejected) {
      return DepositError('Operation ${deposit.operationId} was already processed.');
    }

    final now = DateTime.now().toUtc();
    if (deposit.expiresAt.isBefore(now)) {
      final rejected = _markRejected(deposit, 'Session expired.');
      await store.updateDeposit(rejected);
      return DepositRejected(rejected, 'This deposit session expired.');
    }

    final gates = <String>[];
    if (actualPosition != deposit.expectedPosition) {
      gates.add('Wrong compartment: expected position ${deposit.expectedPosition}.');
    }
    if (weightGrams < minDepositWeightGrams) {
      gates.add('No detectable weight ($weightGrams g).');
    }
    if (!mechanicalConfirmed) {
      gates.add('Mechanical confirmation missing.');
    }

    if (gates.isNotEmpty) {
      final rejected = _markRejected(deposit, gates.join(' '));
      await store.updateDeposit(rejected);
      return DepositRejected(rejected, gates.join(' '));
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
    await store.updateDeposit(confirmed);

    return _award(confirmed, userId);
  }

  /// Records history first so challenge progress includes this deposit, then
  /// awards challenge bonuses (re-reading the user to not clobber the bonus),
  /// and finally awards the base points. Points are only ever written by the
  /// store, never by the client.
  Future<DepositOutcome> _award(Deposit confirmed, String userId) async {
    await store.addHistory(HistoryRow(
      userId: userId,
      event: WasteHistoryEvent(
        id: Ids.record(),
        operationId: confirmed.operationId,
        stationId: confirmed.stationId,
        predictedClass: confirmed.predictedClass,
        weightGrams: confirmed.weightGrams,
        pointsAwarded: confirmed.pointsAwarded,
        createdAt: DateTime.now().toUtc(),
      ),
    ));

    // Challenge bonuses first (persisted atomically by the store).
    final bonus = await store.awardChallengeBonuses(userId);
    final record = store.userById(userId);
    if (record == null) return const DepositError('Unknown user.');

    // Base points on top of the current total (which already includes bonus).
    await store.upsertUser(
      record.copyWith(points: record.user.points + confirmed.pointsAwarded),
    );

    return DepositSuccess(
      confirmed,
      confirmed.pointsAwarded,
      challengeBonus: bonus,
    );
  }

  Deposit _markRejected(Deposit deposit, String reason) => Deposit(
        operationId: deposit.operationId,
        predictionId: deposit.predictionId,
        stationId: deposit.stationId,
        predictedClass: deposit.predictedClass,
        expectedPosition: deposit.expectedPosition,
        actualPosition: deposit.actualPosition == 0 && deposit.status == DepositStatus.pending
            ? 0
            : deposit.actualPosition,
        weightGrams: deposit.weightGrams,
        mechanicalConfirmed: deposit.mechanicalConfirmed,
        potentialPoints: deposit.potentialPoints,
        pointsAwarded: 0,
        status: DepositStatus.rejected,
        expiresAt: deposit.expiresAt,
        rejectReason: reason,
      );
}