import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecoloop/core/api_client.dart';
import 'package:ecoloop/providers/data_providers.dart';
import 'package:ecoloop/providers/providers.dart';
import 'package:ecoloop/screens/leaderboard_screen.dart';
import 'package:ecoloop/services/data_repository.dart';
import 'package:shared/shared.dart';

/// Repairs regression guards for the redesigned leaderboard:
/// podium must render 2nd|1st|3rd with the winner TALLEST, ranks continue
/// correctly below, and the "Your position" footer only appears outside top 3.
class _FakeRepo extends DataRepository {
  final List<LeaderEntry> entries;
  _FakeRepo(this.entries) : super(ApiClient('http://localhost:9'));

  @override
  Future<List<LeaderEntry>> fetchLeaderboard(
          {LeaderScope scope = LeaderScope.students}) async =>
      entries;
}

const _alice = LeaderEntry(
    id: 'a', name: 'Alice One', detail: 'Engineering', points: 100);
const _bob = LeaderEntry(
    id: 'b', name: 'Bob Two', detail: 'Engineering', points: 60);
const _carol = LeaderEntry(
    id: 'c', name: 'Carol Three', detail: 'Art & Design', points: 10);
const _dan =
    LeaderEntry(id: 'me', name: 'Dan Me', detail: 'Engineering', points: 4);

Widget _host(List<LeaderEntry> entries, {String? myId}) {
  return ProviderScope(
    overrides: [
      dataRepositoryProvider.overrideWithValue(_FakeRepo(entries)),
      currentUserIdProvider.overrideWithValue(myId),
    ],
    child: const MaterialApp(home: LeaderboardScreen()),
  );
}

void main() {
  testWidgets('podium shows 2nd | 1st | 3rd with winner tallest',
      (tester) async {
    await tester.pumpWidget(_host([_alice, _bob, _carol], myId: 'nobody'));
    await tester.pumpAndSettle();

    double leftOf(Finder f) => tester.getTopLeft(f).dx;
    expect(leftOf(find.text('Bob Two')),
        lessThan(leftOf(find.text('Alice One'))));
    expect(leftOf(find.text('Alice One')),
        lessThan(leftOf(find.text('Carol Three'))));

    // Cards share a bottom edge, so the taller (better-ranked) card starts
    // higher: winner's name must be ABOVE 2nd place's, 2nd above 3rd's.
    final aliceTop = tester.getTopLeft(find.text('Alice One')).dy;
    final bobTop = tester.getTopLeft(find.text('Bob Two')).dy;
    final carolTop = tester.getTopLeft(find.text('Carol Three')).dy;
    expect(aliceTop, lessThan(bobTop));
    expect(bobTop, lessThan(carolTop));

    // Only the winner wears the crown badge.
    expect(find.byIcon(Icons.workspace_premium), findsOneWidget);

    // Ranks below the podium continue from 4.
    expect(find.text('Dan Me'), findsNothing);
  });

  testWidgets('rows after podium are ranked from 4 and you-row is highlighted',
      (tester) async {
    await tester.pumpWidget(
        _host([_alice, _bob, _carol, _dan], myId: 'me'));
    await tester.pumpAndSettle();

    expect(find.text('Your position'), findsOneWidget);
    expect(find.text('#4'), findsOneWidget);
    expect(find.text('4 pts'), findsWidgets);
  });

  testWidgets('no footer card when you are not on the board', (tester) async {
    await tester.pumpWidget(
        _host([_alice, _bob, _carol, _dan], myId: 'ghost'));
    await tester.pumpAndSettle();

    expect(find.text('Your position'), findsNothing);
  });

  testWidgets('empty leaderboard shows friendly empty state', (tester) async {
    await tester.pumpWidget(_host(const [], myId: 'me'));
    await tester.pumpAndSettle();

    expect(find.text('No rankings yet'), findsOneWidget);
  });
}
