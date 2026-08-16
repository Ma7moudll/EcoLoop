import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('ConfidencePolicy', () {
    test('thresholds match the product spec exactly', () {
      expect(confidenceThresholdsValid, isTrue);
    });

    test('classifies confidence at and above 0.80 as high', () {
      expect(confidenceLevelFor(0.80), ConfidenceLevel.high);
      expect(confidenceLevelFor(0.96), ConfidenceLevel.high);
    });

    test('classifies 0.50..0.80 (exclusive) as medium', () {
      expect(confidenceLevelFor(0.50), ConfidenceLevel.medium);
      expect(confidenceLevelFor(0.73), ConfidenceLevel.medium);
      expect(confidenceLevelFor(0.799), ConfidenceLevel.medium);
    });

    test('classifies below 0.50 as low', () {
      expect(confidenceLevelFor(0.499), ConfidenceLevel.low);
      expect(confidenceLevelFor(0.41), ConfidenceLevel.low);
    });
  });

  group('RoutingPolicy', () {
    test('maps each class to exactly one of the four positions', () {
      expect(positionForClass(WasteClass.plastic), 1);
      expect(positionForClass(WasteClass.metal), 2);
      expect(positionForClass(WasteClass.paper), 3);
      expect(positionForClass(WasteClass.other), 4);
    });

    test('compartment colors and points per spec', () {
      expect(compartmentForClass(WasteClass.plastic).colorName, 'Blue');
      expect(compartmentForClass(WasteClass.plastic).potentialPoints, 5);
      expect(compartmentForClass(WasteClass.metal).potentialPoints, 10);
      expect(compartmentForClass(WasteClass.paper).potentialPoints, 5);
      expect(compartmentForClass(WasteClass.other).potentialPoints, 0);
      expect(compartmentForClass(WasteClass.other).isRecyclable, isFalse);
    });

    test('compartmentState highlights exactly one compartment', () {
      final state = compartmentState(WasteClass.plastic);
      expect(state, hasLength(4));
      expect(state.where((e) => e.$2).toList(), hasLength(1));
      expect(state.firstWhere((e) => e.$2).$1.wasteClass, WasteClass.plastic);
    });

    test('round-trips position -> class', () {
      for (var w in WasteClass.values) {
        expect(
          compartmentForPosition(positionForClass(w)).wasteClass,
          w,
        );
      }
    });
  });

  group('WasteClass', () {
    test('fromApi maps all four classes', () {
      expect(WasteClassX.fromApi('plastic'), WasteClass.plastic);
      expect(WasteClassX.fromApi('metal'), WasteClass.metal);
      expect(WasteClassX.fromApi('paper'), WasteClass.paper);
      expect(WasteClassX.fromApi('other'), WasteClass.other);
      expect(WasteClassX.fromApi('unknown'), WasteClass.other);
    });
  });

  group('Prediction JSON', () {
    test('parses the exact API response shape', () {
      final p = Prediction.fromJson({
        'prediction_id': 'pred_123',
        'operation_id': 'OP-92831',
        'predicted_class': 'plastic',
        'confidence': 0.96,
        'confidence_level': 'high',
        'recyclable': true,
        'destination_position': 1,
        'potential_points': 5,
        'expires_at': '2026-08-16T22:10:00Z',
        'source': 'demo',
      });
      expect(p.predictedClass, WasteClass.plastic);
      expect(p.confidence, 0.96);
      expect(p.confidenceLevel, ConfidenceLevel.high);
      expect(p.destinationPosition, 1);
      expect(p.potentialPoints, 5);
      expect(p.source, 'demo');
    });
  });
}