import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recycle_vision/widgets/app_bottom_nav.dart';
import 'package:recycle_vision/widgets/gamification_cards.dart';
import 'package:recycle_vision/widgets/history_row.dart';
import 'package:recycle_vision/widgets/station/compartment_status.dart';
import 'package:shared/shared.dart';

void main() {
  group('AppBottomNav', () {
    testWidgets('renders five destinations, no scan slot', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: AppBottomNav(currentIndex: 0, onSelected: _noop),
        ),
      ));
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Impact'), findsOneWidget);
      expect(find.text('Rewards'), findsOneWidget);
      expect(find.text('Leaderboard'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      // Scanning moved to the floating action button — not in the bar.
      expect(find.byIcon(Icons.recycling), findsNothing);
    });

    testWidgets('tapping Rewards reports index 2', (tester) async {
      int? selected;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AppBottomNav(
            currentIndex: 0,
            onSelected: (i) => selected = i,
          ),
        ),
      ));
      await tester.tap(find.text('Rewards'));
      expect(selected, 2);
    });

    testWidgets('tapping Profile reports index 4', (tester) async {
      int? selected;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AppBottomNav(
            currentIndex: 0,
            onSelected: (i) => selected = i,
          ),
        ),
      ));
      await tester.tap(find.text('Profile'));
      expect(selected, 4);
    });
  });

  group('CompartmentRack', () {
    testWidgets('shows all four compartments and highlights the target',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: CompartmentRack(openClass: WasteClass.metal),
        ),
      ));
      expect(find.text('PLASTIC'), findsOneWidget);
      expect(find.text('METAL'), findsOneWidget);
      expect(find.text('PAPER'), findsOneWidget);
      expect(find.text('OTHER'), findsOneWidget);
    });
  });

  group('PointsCard', () {
    testWidgets('renders the points value', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: PointsCard(points: 45)),
      ));
      expect(find.text('45'), findsOneWidget);
    });
  });

  group('HistoryRow', () {
    testWidgets('shows label, weight and points', (tester) async {
      final event = WasteHistoryEvent(
        id: 'ev-1',
        operationId: 'OP-TEST',
        stationId: Station.defaultStation.id,
        predictedClass: WasteClass.plastic,
        weightGrams: 18.4,
        pointsAwarded: 5,
        createdAt: DateTime.now().toUtc(),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: HistoryRow(event: event)),
      ));
      expect(find.text('Probably Plastic'), findsOneWidget);

      final event2 = WasteHistoryEvent(
        id: 'ev-2',
        operationId: 'OP-TEST',
        stationId: Station.defaultStation.id,
        predictedClass: WasteClass.other,
        weightGrams: 2.0,
        pointsAwarded: 0,
        createdAt: DateTime.now().toUtc(),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: HistoryRow(event: event2)),
      ));
      expect(find.text('0 pts'), findsOneWidget);
    });
  });

  test('confidence thresholds stay exactly at spec', () {
    expect(confidenceThresholdsValid, isTrue);
    expect(confidenceLevelFor(0.80), ConfidenceLevel.high);
    expect(confidenceLevelFor(0.50), ConfidenceLevel.medium);
    expect(confidenceLevelFor(0.49), ConfidenceLevel.low);
  });
}

void _noop(int _) {}