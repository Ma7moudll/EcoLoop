import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recycle_vision/providers/providers.dart';
import 'package:recycle_vision/screens/scan/deposit_screen.dart';
import 'package:recycle_vision/screens/scan/deposit_success_screen.dart';

import 'helpers.dart';

void main() {
  testWidgets('full deposit flow ends on the success screen', (tester) async {
    final repo = FakeDepositRepository()
      ..outcome = fakeConfirmedDeposit(awarded: 5);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        depositRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        home: DepositScreen(prediction: fakePrediction()),
      ),
    ));

    // Session creation is async.
    await tester.pumpAndSettle();
    expect(find.text('Place the item at the opening'), findsOneWidget);

    // Step 1: place item.
    await tester.tap(find.text('Place the item at the opening'));
    await tester.pump();

    // Step 2: start the drop → confirm → success screen.
    await tester.tap(find.text('Start the drop'));
    await tester.pumpAndSettle();

    expect(find.byType(DepositSuccessScreen), findsOneWidget);
    expect(find.text('Deposit complete!'), findsOneWidget);
    expect(find.textContaining('+5 pts'), findsOneWidget);
  });
}