/// Routing / compartment policy for the single EcoLoop station.
///
/// The station is ONE physical unit with four internal compartments and an
/// internal moving carriage. There is no "one bin per material", so routing
/// is a pure function from the AI's `predicted_class` to an internal
/// compartment position (1..4). This mapping is intentionally separate from
/// the AI provider.
library;

import 'waste_class.dart';

export 'confidence_policy.dart' show ConfidenceLevel;
export 'waste_class.dart' show WasteClass, WasteClassX;

/// Physical compartment inside the EcoLoop station.
class CompartmentSpec {
  final int position;
  final WasteClass wasteClass;
  final String label;
  final String colorName;
  final String colorHex;
  final String emoji;
  final int potentialPoints;

  const CompartmentSpec({
    required this.position,
    required this.wasteClass,
    required this.label,
    required this.colorName,
    required this.colorHex,
    required this.emoji,
    required this.potentialPoints,
  });

  /// Whether this compartment's class is worth points when deposited.
  bool get isRecyclable => wasteClass.isRecyclable;
}

/// Position → compartment definition. Positions are stable within the station.
const Map<int, CompartmentSpec> compartmentByPosition = {
  1: CompartmentSpec(
    position: 1,
    wasteClass: WasteClass.plastic,
    label: 'PLASTIC',
    colorName: 'Blue',
    colorHex: '#2B81DC',
    emoji: '🟦',
    potentialPoints: 5,
  ),
  2: CompartmentSpec(
    position: 2,
    wasteClass: WasteClass.metal,
    label: 'METAL',
    colorName: 'Yellow',
    colorHex: '#F4AD17',
    emoji: '🟨',
    potentialPoints: 10,
  ),
  3: CompartmentSpec(
    position: 3,
    wasteClass: WasteClass.paper,
    label: 'PAPER',
    colorName: 'Green',
    colorHex: '#079548',
    emoji: '🟩',
    potentialPoints: 5,
  ),
  4: CompartmentSpec(
    position: 4,
    wasteClass: WasteClass.other,
    label: 'OTHER',
    colorName: 'Grey',
    colorHex: '#607078',
    emoji: '⬛',
    potentialPoints: 0,
  ),
};

/// Maps a predicted class to its compartment position (1..4).
int positionForClass(WasteClass wasteClass) =>
    compartmentByPosition.values
        .firstWhere((c) => c.wasteClass == wasteClass)
        .position;

/// Maps a predicted class to its full compartment spec.
CompartmentSpec compartmentForClass(WasteClass wasteClass) =>
    compartmentByPosition.values
        .firstWhere((c) => c.wasteClass == wasteClass);

/// Maps a position (1..4) back to its compartment spec.
CompartmentSpec compartmentForPosition(int position) =>
    compartmentByPosition[position]!;

/// Renders every compartment with an open/closed state for the station UI.
List<(CompartmentSpec, bool)> compartmentState(WasteClass openClass) =>
    compartmentByPosition.values
        .map((c) => (c, c.wasteClass == openClass))
        .toList()
      ..sort((a, b) => a.$1.position.compareTo(b.$1.position));