import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecoloop/providers/providers.dart';
import 'package:ecoloop/providers/session_provider.dart';
import 'package:ecoloop/screens/recycle/recycle_flow_screen.dart';
import 'package:ecoloop/screens/recycle/recycle_screen.dart';
import 'package:shared/shared.dart';

import 'helpers.dart';

class _ReadySession extends SessionNotifier {
  @override
  SessionState build() => SessionState.ready(fakeUser());
}

Widget _harness(
  FakeDataRepository data,
  FakeDepositRepository repo,
  FakeDepositStatusChannel channel,
) {
  return ProviderScope(
    overrides: [
      sessionProvider.overrideWith(_ReadySession.new),
      dataRepositoryProvider.overrideWithValue(data),
      depositRepositoryProvider.overrideWithValue(repo),
      depositStatusChannelProvider.overrideWithValue(channel),
    ],
    child: MaterialApp(home: RecycleScreen()),
  );
}

void main() {
  testWidgets('lists stations and starts the flow from the station list',
      (tester) async {
    // Flow screen remains live while the 40ms moving phase streams in, then
    // completes — leaving no pending timers.
    final channel = FakeDepositStatusChannel()
      ..live.add(fakeDeposit(DepositStatus.moving));

    await tester.pumpWidget(_harness(
      FakeDataRepository()
        ..stations = const [
          Station(
              id: 'st-001',
              stationCode: 'ST-001',
              name: 'EcoLoop Station',
              status: 'online'),
        ],
      FakeDepositRepository(),
      channel,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Scan station QR'), findsOneWidget);
    expect(find.text('EcoLoop Station'), findsOneWidget);
    expect(find.text('ST-001'), findsOneWidget);

    await tester.tap(find.text('EcoLoop Station'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // The flow screen is pushed and waiting on the (still live) station.
    expect(find.byType(RecycleFlowScreen), findsOneWidget);
    expect(find.text('Moving to the compartment…'), findsWidgets);

    // Let the 40ms phase complete so no timers are left pending.
    await tester.pumpAndSettle();
  });

  testWidgets('manual station code starts the flow for a known station',
      (tester) async {
    final channel = FakeDepositStatusChannel()
      ..live.add(fakeDeposit(DepositStatus.moving));

    await tester.pumpWidget(_harness(
      FakeDataRepository()
        ..stations = const [
          Station(
              id: 'st-001',
              stationCode: 'ST-001',
              name: 'EcoLoop Station',
              status: 'online'),
        ],
      FakeDepositRepository(),
      channel,
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextField).last, 'st-001'); // lowercase still resolves
    await tester.tap(find.text('Go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.byType(RecycleFlowScreen), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('unknown station code is rejected, no flow started',
      (tester) async {
    final channel = FakeDepositStatusChannel();

    await tester.pumpWidget(_harness(
      FakeDataRepository()
        ..stations = const [
          Station(
              id: 'st-001',
              stationCode: 'ST-001',
              name: 'EcoLoop Station',
              status: 'online'),
        ],
      FakeDepositRepository(),
      channel,
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'ST-999');
    await tester.tap(find.text('Go'));
    await tester.pump();

    expect(find.textContaining('Unknown station'), findsOneWidget);
    expect(find.byType(RecycleFlowScreen), findsNothing);
  });
}