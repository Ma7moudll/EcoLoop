// =============================================================================
// RotaryController — the mechanism abstraction (§22).
//
// MQTT layer -> Station FSM -> RotaryController (HERE) -> stepper driver.
// Non-blocking: routeTo() starts a motion; tick() drives it; isMoving()
// reports progress; timeouts and stall detection live here (§11, §25).
// =============================================================================
#pragma once
#include <AccelStepper.h>

#include "bin_map.h"

enum class RotaryStatus : uint8_t { UNHOMED, HOMING, IDLE, MOVING, JAMMED, ESTOP };

class RotaryController {
 public:
  RotaryController(uint8_t pinStep, uint8_t pinDir, uint8_t pinEnable,
                   uint8_t pinHomeHall, const BinMap& map);

  void begin();
  bool startHoming();          // returns false if already busy
  bool routeToPosition(uint8_t position);  // backend compartment index 1..4
  void tick();                 // call from loop() — never blocks
  void emergencyStop();        // cut driver, enter safe state
  void clearEstop();           // manual recovery after jam/estop

  RotaryStatus status() const { return status_; }
  float angleDeg() const;
  uint8_t mechanismPosition() const;   // compartment index or 0 between slots
  bool isHomed() const { return homed_; }
  bool isMoving() const;

 private:
  bool startMoveTo(float targetDeg);
  void finishMotion(bool ok);
  void stepMotor();

  AccelStepper stepper_;
  uint8_t pinEnable_, pinHomeHall_;
  const BinMap& map_;
  RotaryStatus status_ = RotaryStatus::UNHOMED;
  bool homed_ = false;
  float currentDeg_ = 0.0f;
  float targetDeg_ = 0.0f;
  int32_t targetSteps_ = 0, lastSteps_ = 0;
  uint32_t motionStartMs_ = 0, lastProgressMs_ = 0;
  float moveTimeoutS_ = 6.0f, maxDegPerSec_ = 300.0f, homeBackoffDeg_ = 3.0f,
        homingTimeoutS_ = 12.0f;
};
