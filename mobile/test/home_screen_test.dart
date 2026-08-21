import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recycle_vision/providers/providers.dart';
import 'package:recycle_vision/providers/session_provider.dart';
import 'package:recycle_vision/screens/home_screen.dart';

import 'helpers.dart';

class _ReadySession extends SessionNotifier {
  @override
  SessionState build() => SessionState.ready(fakeUser(points: 60));
}

void main() {
  testWidgets('home renders greeting, points and recent activity',
      (tester) async {
    final data = FakeDataRepository()..user = fakeUser(points: 60);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionProvider.overrideWith(_ReadySession.new),
        dataRepositoryProvider.overrideWithValue(data),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Test'), findsWidgets); // greeting
    expect(find.text('60'), findsOneWidget); // points from server
    expect(find.text('Probably Plastic'), findsOneWidget); // history row
    expect(find.text('Recycle now'), findsOneWidget); // CTA
    expect(find.text('0.6 kg'), findsOneWidget); // impact recycled kg

    // The challenge card lives lower in the lazy list; scroll to reveal it.
    await tester.scrollUntilVisible(
      find.text('Plastic Race'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Plastic Race'), findsOneWidget); // challenge
  });
}