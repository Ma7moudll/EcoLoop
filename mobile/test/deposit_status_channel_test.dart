import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart' show DelegatingStreamSink;
import 'package:flutter_test/flutter_test.dart';
import 'package:recycle_vision/core/api_client.dart';
import 'package:recycle_vision/services/data_repository.dart';
import 'package:recycle_vision/services/deposit_status_channel.dart';
import 'package:shared/shared.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Minimal in-memory WebSocketChannel for exercising the status channel
/// without touching the network.
class FakeSocket extends StreamChannelMixin implements WebSocketChannel {
  FakeSocket(this._ctrl);

  final StreamController<Object?> _ctrl;

  @override
  Stream<dynamic> get stream => _ctrl.stream;

  @override
  WebSocketSink get sink => _FakeSink(_ctrl.sink);

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready async {}

  // Structural witness for WebSocketChannel.close (the mixin also names a
  // compatible close(), so this deliberately carries no @override).
  Future close([int? closeCode, String? closeReason]) async {
    await _ctrl.close();
  }
}

class _FakeSink extends DelegatingStreamSink implements WebSocketSink {
  _FakeSink(super.inner);

  @override
  Future close([int? closeCode, String? closeReason]) => super.close();
}

/// Records whether the HTTP-polling fallback was used.
class TrackingDepositRepository extends DepositRepository {
  TrackingDepositRepository(this.outcome)
      : super(ApiClient('http://localhost:9999'));

  final ({Deposit deposit, int pointsAwarded, int challengeBonus}) outcome;
  int polls = 0;

  @override
  Future<({Deposit deposit, int pointsAwarded, int challengeBonus})>
      awaitDeposit(
    Deposit session, {
    Duration pollInterval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 3),
  }) async {
    polls++;
    return outcome;
  }
}

Deposit _live(DepositStatus status) => Deposit(
      operationId: 'OP-TEST',
      predictionId: 'pred-test',
      stationId: 'st-001',
      predictedClass: WasteClass.plastic,
      expectedPosition: 1,
      actualPosition: 0,
      weightGrams: 0,
      mechanicalConfirmed: false,
      potentialPoints: 5,
      pointsAwarded: 0,
      status: status,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );

Deposit _confirmed() => Deposit(
      operationId: 'OP-TEST',
      predictionId: 'pred-test',
      stationId: 'st-001',
      predictedClass: WasteClass.plastic,
      expectedPosition: 1,
      actualPosition: 1,
      weightGrams: 18.4,
      mechanicalConfirmed: true,
      potentialPoints: 5,
      pointsAwarded: 5,
      status: DepositStatus.confirmed,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );

void main() {
  group('phaseLabel', () {
    test('maps every live phase to copy', () {
      expect(DepositStatusChannel.phaseLabel(DepositStatus.routing),
          'Routing the item…');
      expect(DepositStatusChannel.phaseLabel(DepositStatus.moving),
          'Moving to the compartment…');
      expect(DepositStatusChannel.phaseLabel(DepositStatus.measuring),
          'Measuring weight…');
    });
  });

  group('awaitDeposit', () {
    test('streams live states then returns the terminal confirmed deposit',
        () async {
      final ctrl = StreamController<Object?>(sync: true);
      ctrl.add(jsonEncode({'type': 'subscribed', 'operation_id': 'OP-TEST'}));
      ctrl.add(jsonEncode(
          {'type': 'state', 'deposit': _live(DepositStatus.routing).toJson()}));
      ctrl.add(jsonEncode(
          {'type': 'state', 'deposit': _live(DepositStatus.measuring).toJson()}));
      ctrl.add(jsonEncode(
          {'type': 'terminal', 'deposit': _confirmed().toJson()}));

      final repo = TrackingDepositRepository(
          (deposit: _confirmed(), pointsAwarded: 5, challengeBonus: 0));
      final channel = DepositStatusChannel(
        ApiClient('http://localhost:8080/api/v1')..setToken('tok'),
        repo,
        connect: (_) => FakeSocket(ctrl),
      );

      final seen = <DepositStatus>[];
      final result = await channel.awaitDeposit(
        _live(DepositStatus.pending),
        onLive: (live) => seen.add(live.status),
      );

      expect(seen, [DepositStatus.routing, DepositStatus.measuring]);
      expect(result.deposit.status, DepositStatus.confirmed);
      expect(result.pointsAwarded, 5);
      expect(repo.polls, 0); // socket path used, polling never engaged
      await ctrl.close();
    });

    test('forwards a rejected terminal and never awards points', () async {
      final rejected = Deposit(
        operationId: 'OP-TEST',
        predictionId: 'pred-test',
        stationId: 'st-001',
        predictedClass: WasteClass.plastic,
        expectedPosition: 1,
        actualPosition: 2,
        weightGrams: 0,
        mechanicalConfirmed: false,
        potentialPoints: 5,
        pointsAwarded: 0,
        status: DepositStatus.rejected,
        rejectReason: 'wrong_position: expected compartment 1, got 2',
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      );
      final ctrl = StreamController<Object?>(sync: true);
      ctrl.add(jsonEncode({'type': 'terminal', 'deposit': rejected.toJson()}));

      final repo = TrackingDepositRepository(
          (deposit: rejected, pointsAwarded: 0, challengeBonus: 0));
      final channel = DepositStatusChannel(
        ApiClient('http://localhost:8080/api/v1')..setToken('tok'),
        repo,
        connect: (_) => FakeSocket(ctrl),
      );

      final result = await channel.awaitDeposit(_live(DepositStatus.pending));
      expect(result.deposit.status, DepositStatus.rejected);
      expect(result.pointsAwarded, 0);
      expect(repo.polls, 0);
      await ctrl.close();
    });

    test('falls back to HTTP polling when the socket fails', () async {
      final ctrl = StreamController<Object?>(sync: true);
      ctrl.addError(WebSocketChannelException('connection refused'));
      ctrl.close();

      final repo = TrackingDepositRepository(
          (deposit: _confirmed(), pointsAwarded: 5, challengeBonus: 0));
      final channel = DepositStatusChannel(
        ApiClient('http://localhost:8080/api/v1')..setToken('tok'),
        repo,
        connect: (_) => FakeSocket(ctrl),
      );

      final result = await channel.awaitDeposit(_live(DepositStatus.pending));
      expect(result.deposit.status, DepositStatus.confirmed);
      expect(repo.polls, 1); // polling took over
    });

    test('polls immediately when no auth token is available', () async {
      var connected = false;
      final repo = TrackingDepositRepository(
          (deposit: _confirmed(), pointsAwarded: 5, challengeBonus: 0));
      final channel = DepositStatusChannel(
        ApiClient('http://localhost:8080/api/v1'), // no token
        repo,
        connect: (_) {
          connected = true;
          return FakeSocket(StreamController<Object?>());
        },
      );

      final result = await channel.awaitDeposit(_live(DepositStatus.pending));
      expect(result.deposit.status, DepositStatus.confirmed);
      expect(connected, false); // no token -> socket never attempted
      expect(repo.polls, 1);
    });
  });
}
