#include "rotary_controller.h"

RotaryController::RotaryController(uint8_t pinStep, uint8_t pinDir,
                                   uint8_t pinEnable, uint8_t pinHomeHall,
                                   const BinMap& map)
    : stepper_(AccelStepper::DRIVER, pinStep, pinDir),
      pinEnable_(pinEnable),
      pinHomeHall_(pinHomeHall),
      map_(map) {}

void RotaryController::begin() {
  pinMode(pinEnable_, OUTPUT);
  pinMode(pinHomeHall_, INPUT_PULLUP);
  digitalWrite(pinEnable_, HIGH);  // driver disabled until needed
  stepper_.setMaxSpeed(maxDegPerSec_);
  stepper_.setAcceleration(1000.0f);
}

bool RotaryController::startHoming() {
  if (status_ == RotaryStatus::ESTOP || isMoving()) return false;
  status_ = RotaryStatus::HOMING;
  // Seek CCW (negative) slowly until the Hall fires; handled in tick().
  stepper_.setMaxSpeed(60.0f);
  stepper_.move(-0x7FFFFFFF);  // continuous CCW until we stop it
  motionStartMs_ = millis();
  lastProgressMs_ = motionStartMs_;
  return true;
}

bool RotaryController::routeToPosition(uint8_t position) {
  if (!homed_ || isMoving() || status_ == RotaryStatus::ESTOP) return false;
  const BinTarget& t = map_.targetForPosition(position);
  return startMoveTo(t.angleDeg);
}

bool RotaryController::startMoveTo(float targetDeg) {
  float delta = map_.shortestDelta(currentDeg_, targetDeg);
  if (fabsf(delta) < map_.degreesPerStep() / 2.0f) {
    return true;  // already aligned — idempotent (§21)
  }
  float seconds = fabsf(delta) / maxDegPerSec_;
  if (seconds > moveTimeoutS_) {
    status_ = RotaryStatus::JAMMED;  // refuse moves outside the safety envelope
    return false;
  }
  targetSteps_ = map_.stepsForDelta(delta);
  targetDeg_ = targetDeg;
  stepper_.setMaxSpeed(maxDegPerSec_);
  stepper_.move(targetSteps_);
  motionStartMs_ = millis();
  lastProgressMs_ = motionStartMs_;
  lastSteps_ = stepper_.currentPosition();
  status_ = RotaryStatus::MOVING;
  return true;
}

void RotaryController::tick() {
  if (status_ == RotaryStatus::HOMING) {
    stepMotor();
    bool hallHit = digitalRead(pinHomeHall_) == LOW;
    uint32_t now = millis();
    if (now - motionStartMs_ > homingTimeoutS_ * 1000.0f) {
      stepper_.stop();  // §25: never seek forever
      emergencyStop();
      return;
    }
    if (hallHit) {
      stepper_.setCurrentPosition(0);   // hard reference = zero steps
      currentDeg_ = 0.0f;
      startMoveTo(homeBackoffDeg_);     // settle onto the exact mark
      status_ = RotaryStatus::HOMING;   // stay until backoff completes
      if (stepper_.distanceToGo() == 0) {
        currentDeg_ = homeBackoffDeg_;
        startMoveTo(0.0f);
        if (stepper_.distanceToGo() == 0) finishMotion(true);
      }
      return;
    }
    if (stepper_.speed() == 0 && now - lastProgressMs_ > 500) {
      emergencyStop();  // stalled against an unexpected obstruction
    }
    return;
  }

  if (status_ != RotaryStatus::MOVING) return;
  stepMotor();

  // Progress watchdog: no step progress within the timeout => jam (§25).
  int32_t pos = stepper_.currentPosition();
  if (pos != lastSteps_) {
    lastSteps_ = pos;
    lastProgressMs_ = millis();
  }
  uint32_t now = millis();
  if (now - motionStartMs_ > moveTimeoutS_ * 1000.0f ||
      now - lastProgressMs_ > moveTimeoutS_ * 1000.0f) {
    stepper_.stop();
    emergencyStop();
    status_ = RotaryStatus::JAMMED;
    return;
  }
  if (stepper_.distanceToGo() == 0) {
    currentDeg_ = targetDeg_;
    finishMotion(true);
  }
}

void RotaryController::finishMotion(bool ok) {
  if (ok && status_ == RotaryStatus::HOMING) {
    homed_ = true;
    status_ = RotaryStatus::IDLE;
  } else if (ok) {
    status_ = RotaryStatus::IDLE;
  }
}

void RotaryController::emergencyStop() {
  stepper_.stop();
  digitalWrite(pinEnable_, HIGH);  // release the motor — safe state
  if (status_ != RotaryStatus::HOMING || !homed_) status_ = RotaryStatus::ESTOP;
}

void RotaryController::clearEstop() { status_ = homed_ ? RotaryStatus::IDLE : RotaryStatus::UNHOMED; }

void RotaryController::stepMotor() {
  digitalWrite(pinEnable_, LOW);  // energize while moving
  stepper_.run();
  if (stepper_.distanceToGo() == 0 && status_ != RotaryStatus::MOVING) {
    digitalWrite(pinEnable_, HIGH);  // de-energize at rest (thermal)
  }
  currentDeg_ += 0;  // angle tracked via steps in finishMotion/target
}

float RotaryController::angleDeg() const { return currentDeg_; }

uint8_t RotaryController::mechanismPosition() const {
  for (uint8_t i = 1; i <= 4; ++i) {
    if (fabsf(map_.shortestDelta(currentDeg_, map_.targetForPosition(i).angleDeg)) < 1.0f)
      return i;
  }
  return 0;
}

bool RotaryController::isMoving() const {
  return status_ == RotaryStatus::MOVING || status_ == RotaryStatus::HOMING;
}
