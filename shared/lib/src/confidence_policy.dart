/// Confidence classification policy.
///
/// Exact thresholds from the product spec:
/// - `confidence >= 0.80`            → HIGH   → accepted automatically
/// - `0.50 <= confidence < 0.80`     → MEDIUM → retake or manually confirm
/// - `confidence < 0.50`             → LOW    → unknown / retake
library;

enum ConfidenceLevel {
  high('high'),
  medium('medium'),
  low('low');

  final String apiValue;
  const ConfidenceLevel(this.apiValue);

  static ConfidenceLevel fromApi(String value) => switch (value) {
        'high' => ConfidenceLevel.high,
        'medium' => ConfidenceLevel.medium,
        _ => ConfidenceLevel.low,
      };
}

const double highConfidenceThreshold = 0.80;
const double mediumConfidenceThreshold = 0.50;

ConfidenceLevel confidenceLevelFor(double confidence) {
  if (confidence >= highConfidenceThreshold) return ConfidenceLevel.high;
  if (confidence >= mediumConfidenceThreshold) return ConfidenceLevel.medium;
  return ConfidenceLevel.low;
}

/// Configured thresholds are never allowed to drift from the spec.
bool get confidenceThresholdsValid =>
    highConfidenceThreshold == 0.80 && mediumConfidenceThreshold == 0.50;