/// The four coarse waste classes recognized by EcoLoop.
///
/// This is the single source of truth for the detected waste class.
/// The AI provider returns `predicted_class` and everything else derives
/// from it (routing, labels, potential points). There is no duplicate
/// `material` field.
enum WasteClass { plastic, metal, paper, other }

extension WasteClassX on WasteClass {
  /// API value used in JSON payloads (matches `predicted_class`).
  String get apiValue => name;

  /// Human-readable label shown in the UI.
  String get label => switch (this) {
        WasteClass.plastic => 'Plastic',
        WasteClass.metal => 'Metal',
        WasteClass.paper => 'Paper',
        WasteClass.other => 'Other',
      };

  /// Short display label used in results, e.g. "Probably Plastic".
  String get probableLabel => 'Probably $label';

  /// Whether this class is worth points when deposited.
  bool get isRecyclable => this != WasteClass.other;

  static WasteClass fromApi(String value) => switch (value) {
        'plastic' => WasteClass.plastic,
        'metal' => WasteClass.metal,
        'paper' => WasteClass.paper,
        _ => WasteClass.other,
      };
}