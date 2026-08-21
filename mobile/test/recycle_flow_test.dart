import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recycle_vision/providers/providers.dart';
import 'package:recycle_vision/screens/recycle/deposit_result_screen.dart';
import 'package:recycle_vision/screens/recycle/recycle_flow_screen.dart';
import 'package:recycle_vision/services/deposit_status_channel.dart';
import 'package:shared/shared.dart';

import 'helpers.dart';

Widget _harness(
  FakeDepositRepository repo,
  FakeDepositStatusChannel channel, {
  Station? station,
}) {
  return ProviderScope(
    overrides: [
      depositRepositoryProvider.overrideWithValue(repo),
      depositStatusChannelProvider.overrideWithValue(channel),
    ],
    child: MaterialApp(
      home: RecycleFlowScreen(station: station ?? Station.defaultStation),
    ),
  );
}

void main() {
  test('phaseLabel covers the station-camera capture/analyzing phases', () {
    expect(DepositStatusChannel.phaseLabel(DepositStatus.capture),
        contains('station camera'));
    expect(DepositStatusChannel.phaseLabel(DepositStatus.analyzing),
        contains('Analyzing'));
    expect(DepositStatus.capture.isCapturePhase, isTrue);
    expect(DepositStatus.analyzing.isCapturePhase, isTrue);
    expect(DepositStatus.routing.isCapturePhase, isFalse);
  });

  testWidgets('station-camera flow: analyzing -> routing -> success',
      (tester) async {
    final repo = FakeDepositRepository()
      ..session = fakeDeposit(DepositStatus.capture);
    final channel = FakeDepositStatusChannel()
      ..live.add(fakeDeposit(DepositStatus.analyzing))
      ..live.add(fakeDeposit(DepositStatus.routing))
      ..live.add(fakeDeposit(DepositStatus.measuring))
      ..outcome = (
        deposit: fakeConfirmedDeposit(awarded: 5),
        pointsAwarded: 5,
        challengeBonus: 0,
      );

    await tester.pumpWidget(_harness(repo, channel));
    await tester.pump(); // session creates capture-first, then camera classifies

    expect(find.text('Analyzing the item…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Routing the item…'), findsOneWidget);
    expect(find.text('Routing to compartment #1'), findsOneWidget);
    expect(find.text('PLASTIC'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Measuring weight…'), findsWidgets);

    await tester.pumpAndSettle();
    expect(find.byType(DepositResultScreen), findsOneWidget);
    expect(find.text('Deposit complete!'), findsOneWidget);
    expect(find.textContaining('+5 pts'), findsOneWidget);
  });

  testWidgets('gate rejection surfaces an error, never a success', (tester) async {
    final channel = FakeDepositStatusChannel()
      ..outcome = (
        deposit: fakeDeposit(
          DepositStatus.rejected,
          rejectReason: 'not_clear: retake the photo',
        ),
        pointsAwarded: 0,
        challengeBonus: 0,
      );

    await tester.pumpWidget(
        _harness(FakeDepositRepository(), channel));
    await tester.pumpAndSettle();

    expect(find.byType(DepositResultScreen), findsOneWidget);
    expect(find.text('Deposit rejected'), findsOneWidget);
    expect(find.textContaining('not_clear'), findsOneWidget);
    expect(find.textContaining('+5'), findsNothing);
  });

  testWidgets('session-creation failure shows a retry, never fabricates points',
      (tester) async {
    final repo = _ThrowingDepositRepository();
    await tester.pumpWidget(_harness(repo, FakeDepositStatusChannel()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not start the session'),
        findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byType(DepositResultScreen), findsNothing);
  });

  testWidgets('expired terminal shows the expiry message, never success',
      (tester) async {
    final channel = FakeDepositStatusChannel()
      ..outcome = (
        deposit: fakeDeposit(DepositStatus.expired),
        pointsAwarded: 0,
        challengeBonus: 0,
      );

    await tester.pumpWidget(_harness(FakeDepositRepository(), channel));
    await tester.pumpAndSettle();

    expect(find.text('Deposit expired'), findsOneWidget);
    expect(find.textContaining('session timed out'), findsOneWidget);
    expect(find.textContaining('+5'), findsNothing);
  });

  testWidgets('cancelled terminal shows the cancellation message',
      (tester) async {
    final channel = FakeDepositStatusChannel()
      ..outcome = (
        deposit: fakeDeposit(DepositStatus.cancelled),
        pointsAwarded: 0,
        challengeBonus: 0,
      );

    await tester.pumpWidget(_harness(FakeDepositRepository(), channel));
    await tester.pumpAndSettle();

    expect(find.text('Deposit cancelled'), findsOneWidget);
    expect(find.textContaining('Nothing was awarded'), findsOneWidget);
    expect(find.textContaining('+5'), findsNothing);
  });
}

class _ThrowingDepositRepository extends FakeDepositRepository {
  @override
  Future<Deposit> createSession(
      {String? predictionId, required String stationId}) async {
    throw Exception('backend unreachable');
  }
}