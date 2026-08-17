import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recycle_vision/providers/providers.dart';
import 'package:recycle_vision/screens/scan/deposit_screen.dart';
import 'package:recycle_vision/screens/scan/deposit_success_screen.dart';
import 'package:shared/shared.dart';

import 'helpers.dart';

Widget _harness(FakeDepositStatusChannel channel, FakeDepositRepository repo) {
  return ProviderScope(
    overrides: [
      depositRepositoryProvider.overrideWithValue(repo),
      depositStatusChannelProvider.overrideWithValue(channel),
    ],
    child: MaterialApp(
      home: DepositScreen(prediction: fakePrediction()),
    ),
  );
}

Future<void> _startDrop(
  WidgetTester tester,
  FakeDepositStatusChannel channel,
  FakeDepositRepository repo,
) async {
  await tester.pumpWidget(_harness(channel, repo));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Place the item at the opening'));
  await tester.pump();
  await tester.tap(find.text('Start the drop'));
}

void main() {
  testWidgets('live machine phases stream in over the WebSocket while waiting',
      (tester) async {
    final channel = FakeDepositStatusChannel()
      ..live.add(fakeDeposit(DepositStatus.routing))
      ..live.add(fakeDeposit(DepositStatus.moving))
      ..live.add(fakeDeposit(DepositStatus.measuring));

    await _startDrop(tester, channel, FakeDepositRepository());
    await tester.pump(); // waiting phase begins
    expect(find.text('Routing the item…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Moving to the compartment…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Measuring weight…'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(DepositSuccessScreen), findsOneWidget);
  });

  testWidgets('no success screen or points text before confirmation',
      (tester) async {
    final channel = FakeDepositStatusChannel()
      ..live.add(fakeDeposit(DepositStatus.detecting))
      ..phaseDelay = const Duration(seconds: 30);

    await tester.pumpWidget(_harness(channel, FakeDepositRepository()));
    await tester.pump(); // session creation resolves -> ready
    await tester.tap(find.text('Place the item at the opening'));
    await tester.pump();
    await tester.tap(find.text('Start the drop'));
    await tester.pump(); // waiting phase, first live frame handled

    expect(find.text('Detecting the item…'), findsOneWidget);
    expect(find.byType(DepositSuccessScreen), findsNothing);
    expect(find.textContaining('+5'), findsNothing);

    // Still mid-drop: the 30s simulated machine has not finished.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(DepositSuccessScreen), findsNothing);
    expect(find.textContaining('+5'), findsNothing);

    // Let the simulated machine finish so the test leaves no pending timers.
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
  });

  testWidgets('rejected terminal shows the reason and a retry, never success',
      (tester) async {
    final channel = FakeDepositStatusChannel()
      ..outcome = (
        deposit: fakeDeposit(
          DepositStatus.rejected,
          actualPosition: 2,
          rejectReason: 'wrong_position: expected compartment 1, got 2',
        ),
        pointsAwarded: 0,
        challengeBonus: 0,
      )
      ..live.add(fakeDeposit(DepositStatus.moving));

    await _startDrop(tester, channel, FakeDepositRepository());
    await tester.pumpAndSettle();

    expect(find.byType(DepositSuccessScreen), findsNothing);
    expect(find.text('wrong_position: expected compartment 1, got 2'),
        findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('+5'), findsNothing);
  });

  testWidgets('expired terminal shows the expiry message', (tester) async {
    final channel = FakeDepositStatusChannel()
      ..outcome = (
        deposit: fakeDeposit(DepositStatus.expired),
        pointsAwarded: 0,
        challengeBonus: 0,
      );

    await _startDrop(tester, channel, FakeDepositRepository());
    await tester.pumpAndSettle();

    expect(find.byType(DepositSuccessScreen), findsNothing);
    expect(find.text('Deposit expired before completion.'), findsOneWidget);
  });

  testWidgets('cancelled terminal shows the cancellation message',
      (tester) async {
    final channel = FakeDepositStatusChannel()
      ..outcome = (
        deposit: fakeDeposit(DepositStatus.cancelled),
        pointsAwarded: 0,
        challengeBonus: 0,
      );

    await _startDrop(tester, channel, FakeDepositRepository());
    await tester.pumpAndSettle();

    expect(find.byType(DepositSuccessScreen), findsNothing);
    expect(find.text('Deposit cancelled.'), findsOneWidget);
  });

  testWidgets('status channel falling back to polling still completes',
      (tester) async {
    // No channel override: with a null token the screen falls back to the
    // repository's HTTP polling (FakeDepositRepository returns confirmed).
    final repo = FakeDepositRepository()..outcome = fakeConfirmedDeposit();

    await tester.pumpWidget(ProviderScope(
      overrides: [depositRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: DepositScreen(prediction: fakePrediction()),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Place the item at the opening'));
    await tester.pump();
    await tester.tap(find.text('Start the drop'));
    await tester.pumpAndSettle();

    expect(find.byType(DepositSuccessScreen), findsOneWidget);
    expect(find.text('Deposit complete!'), findsOneWidget);
  });
}
