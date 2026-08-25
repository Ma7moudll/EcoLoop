// =============================================================================
// BinMap — the calibration layer (§10). The ONLY place where bins map to
// angles/steps. Firmware logic never touches raw steps.
// =============================================================================
#pragma once
#include <Arduino.h>

enum class Bin : uint8_t { PLASTIC = 0, METAL, PAPER, OTHER, COUNT };

struct BinTarget {
  Bin bin;
  uint8_t position;   // backend compartment index 1..4
  float angleDeg;     // home-relative, clockwise positive
};

struct BinMapConfig {
  float stepsPerRev;
  uint16_t microstepping;
  float gearRatio;
  float binAnglesDeg[4];
};

class BinMap {
 public:
  explicit BinMap(const BinMapConfig& cfg);

  const BinTarget& targetForPosition(uint8_t position) const;  // 1..4
  // Shortest signed path current->target in degrees (±180).
  float shortestDelta(float currentDeg, float targetDeg) const;
  // Whole shaft steps for a delta (rounded).
  int32_t stepsForDelta(float deltaDeg) const;
  float degreesPerStep() const;

 private:
  static float norm360(float a);
  BinMapConfig cfg_;
  BinTarget targets_[4];
};
