#include "bin_map.h"

BinMap::BinMap(const BinMapConfig& cfg) : cfg_(cfg) {
  for (uint8_t i = 0; i < 4; ++i) {
    targets_[i] = BinTarget{static_cast<Bin>(i), static_cast<uint8_t>(i + 1),
                            norm360(cfg.binAnglesDeg[i])};
  }
}

const BinTarget& BinMap::targetForPosition(uint8_t position) const {
  // position 1..4 -> index 0..3
  return targets_[position - 1];
}

float BinMap::shortestDelta(float currentDeg, float targetDeg) const {
  float d = norm360(targetDeg - currentDeg);
  if (d > 180.0f) d -= 360.0f;
  return d;
}

int32_t BinMap::stepsForDelta(float deltaDeg) const {
  return static_cast<int32_t>(lroundf(deltaDeg / degreesPerStep()));
}

float BinMap::degreesPerStep() const {
  return 360.0f / (cfg_.stepsPerRev * cfg_.microstepping * cfg_.gearRatio);
}

float BinMap::norm360(float a) {
  float r = fmodf(a, 360.0f);
  if (r < 0) r += 360.0f;
  return r;
}
