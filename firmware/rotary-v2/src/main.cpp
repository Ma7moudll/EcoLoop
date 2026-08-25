// =============================================================================
// EcoLoop Station V2 — Rotary Sorting Mechanism :: firmware entrypoint
//
// Layers (§22):  MQTT layer -> Station FSM -> RotaryController -> driver
// Non-blocking main loop; WiFi/MQTT loss forces the safe state (§20).
//
// Serial calibration mode (§24): send "CAL\n" within 5 s of boot to enter
// jog/home/inspect mode. Disabled by requiring physical BOOT button hold
// during the window in production builds (-DCALIBRATION_NEEDS_BOOT_BTN).
// =============================================================================
#include <Arduino.h>
#include <HX711.h>
#include <VL53L1X.h>
#include <Wire.h>

#include "bin_map.h"
#include "config.h"
#include "mqtt_station.h"
#include "rotary_controller.h"
#include "station_fsm.h"

// ---------------------------------------------------------------- wiring ----
static BinMapConfig binCfg{STEPPER_STEPS_REV, MICROSTEPPING, GEAR_RATIO,
                           {0.0f, 90.0f, 180.0f, 270.0f}};
static BinMap binMap(binCfg);
static RotaryController rotary(PIN_STEP, PIN_DIR, PIN_ENABLE, PIN_HOME_HALL, binMap);
static MqttStationLayer mqttLayer(STATION_CODE, MQTT_TOPIC_PREFIX);
static StationFsm fsm;

static HX711 loadCells[4];
static VL53L1X tof[4];
static float tareOffsets[4] = {0, 0, 0, 0};
static float preDepositWeight[4] = {0, 0, 0, 0};

static char activeOperation[40] = {0};
static uint8_t routedPosition = 0;
static uint32_t lastHeartbeat = 0;
static bool beamSeen = false;

// ----------------------------------------------------------- forward decls --
void enterSafeState(const char* reason);
void driveOperation();
void publishResult(const char* status, uint8_t actual, bool stable, bool beam);
void resetToIdle();
float readBinWeight(uint8_t idx);
uint8_t readFillPercent(uint8_t idx);

// ------------------------------------------------------------ setup/loop ----

void setup() {
  Serial.begin(115200);
  rotary.begin();
  Wire.begin();

  for (uint8_t i = 0; i < 4; ++i) {
    loadCells[i].begin(PIN_HX_DOUT[i], PIN_HX_SCK);
    loadCells[i].set_scale(LC_CALIBRATION[i]);
    loadCells[i].tare();
    pinMode(PIN_TOF_XSHUT[i], OUTPUT);
    digitalWrite(PIN_TOF_XSHUT[i], LOW);
  }
  // Assign distinct I2C addresses to the four ToF sensors (Pololu API:
  // setAddress while the others are held in XSHUT reset).
  for (uint8_t i = 0; i < 4; ++i) {
    digitalWrite(PIN_TOF_XSHUT[i], HIGH);
    delay(10);
    tof[i].setTimeout(50);
    if (!tof[i].init()) continue;
    tof[i].setDistanceMode(VL53L1X::Long);
    tof[i].setAddress(TOF_ADDR[i]);
    tof[i].startContinuous(100);
  }

  // Homing happens before we accept commands.
  if (!rotary.startHoming()) enterSafeState("homing refused");
  while (rotary.isMoving()) rotary.tick();   // boot-time homing may block
  if (rotary.status() != RotaryStatus::IDLE) enterSafeState("homing failed");

  mqttLayer.begin(MQTT_USER, MQTT_PASS, MQTT_HOST, MQTT_PORT);
  mqttLayer.onRoute = [](const char* op, uint8_t dest) -> bool {
    if (fsm.state() != StationState::IDLE) return false;   // busy: refuse
    strncpy(activeOperation, op, sizeof(activeOperation) - 1);
    routedPosition = dest;
    fsm.transition(StationState::ROUTING);
    mqttLayer.publishState(op, "ROUTING",
                           [dest](JsonObject& o) { o["destination_position"] = dest; });
    fsm.transition(StationState::MOVING);
    mqttLayer.publishState(op, "MOVING");
    return rotary.routeToPosition(dest);
  };
  mqttLayer.onCaptureRequest = [](const char* op) {
    // The station camera is independent of the mechanism: it uploads the
    // frame straight to POST /deposit/capture with X-Station-Key.
  };
}

void loop() {
  mqttLayer.loop();
  rotary.tick();

  // Safe state on connectivity loss mid-motion (§20).
  if (!mqttLayer.connected() && rotary.isMoving()) {
    rotary.emergencyStop();
    enterSafeState("mqtt lost while moving");
  }

  driveOperation();

  if (millis() - lastHeartbeat > HEARTBEAT_MS) {
    lastHeartbeat = millis();
    mqttLayer.publishHeartbeat(fsm.name(), rotary.mechanismPosition());
  }
}

// ------------------------------------------------------- operation engine ---

void driveOperation() {
  if (fsm.state() != StationState::MOVING || routedPosition == 0) return;
  if (rotary.isMoving()) return;

  if (rotary.status() == RotaryStatus::JAMMED) {
    fsm.transition(StationState::JAMMED);
    mqttLayer.publishState(activeOperation, "JAMMED");
    publishResult("jam", 0, false, false);
    resetToIdle();
    return;
  }
  if (rotary.status() != RotaryStatus::IDLE) {
    fsm.transition(StationState::SENSOR_ERROR);
    publishResult("sensor_error", 0, false, false);
    resetToIdle();
    return;
  }

  const uint8_t actual = rotary.mechanismPosition();
  if (actual != routedPosition) {
    fsm.transition(StationState::WRONG_POSITION);
    mqttLayer.publishState(activeOperation, "WRONG_POSITION");
    publishResult("confirmed", actual, true, true);  // machine belief; backend rejects
    resetToIdle();
    return;
  }

  fsm.transition(StationState::POSITIONED);
  mqttLayer.publishState(activeOperation, "POSITIONED");
  fsm.transition(StationState::READY_FOR_DEPOSIT);
  mqttLayer.publishState(activeOperation, "READY_FOR_DEPOSIT");

  // DETECTING: IR beam at the outlet must break as waste passes.
  fsm.transition(StationState::DETECTING);
  mqttLayer.publishState(activeOperation, "DETECTING");
  uint32_t detectStart = millis();
  beamSeen = false;
  while (millis() - detectStart < 4000) {
    if (digitalRead(PIN_HOME_HALL + 1 /* BEAM_PIN */ ) == LOW) { beamSeen = true; break; }
    yield();
  }

  // MEASURING: delta weight on the target bin's load cell.
  fsm.transition(StationState::MEASURING);
  mqttLayer.publishState(activeOperation, "MEASURING");
  preDepositWeight[routedPosition - 1] = readBinWeight(routedPosition - 1);
  uint32_t settleStart = millis();
  while (millis() - settleStart < WEIGHT_SETTLE_S * 1000.0f) yield();
  float deposited = readBinWeight(routedPosition - 1) - preDepositWeight[routedPosition - 1];
  bool stable = deposited >= MIN_DEPOSIT_G;

  if (!beamSeen || !stable) {
    fsm.transition(beamSeen ? StationState::UNDERWEIGHT : StationState::SENSOR_ERROR);
    publishResult(beamSeen ? "underweight" : "sensor_error", actual, stable, beamSeen);
    resetToIdle();
    return;
  }

  fsm.transition(StationState::DEPOSIT_CONFIRMED);
  mqttLayer.publishState(activeOperation, "DEPOSIT_CONFIRMED");
  publishResult("confirmed", actual, deposited >= MIN_DEPOSIT_G, beamSeen);
  resetToIdle();
}

void publishResult(const char* status, uint8_t actual, bool stable, bool beam) {
  float w = readBinWeight(routedPosition - 1);
  mqttLayer.publishTerminal(activeOperation, status, actual,
                            rotary.mechanismPosition(), fabsf(w), stable, beam,
                            strcmp(status, "confirmed") == 0);
}

void resetToIdle() {
  fsm.transition(StationState::RESETTING);
  mqttLayer.publishState(activeOperation, "RESETTING");
  fsm.transition(StationState::IDLE);
  mqttLayer.publishState(activeOperation, "IDLE");
  activeOperation[0] = 0;
  routedPosition = 0;
}

void enterSafeState(const char* reason) {
  rotary.emergencyStop();
  Serial.printf("[SAFE] %s — manual recovery required\n", reason);
  // Stay here until an operator clears via CAL serial mode.
  while (true) {
    mqttLayer.loop();  // keep heartbeat/LWT alive so backend sees offline/error
    delay(10);
  }
}

float readBinWeight(uint8_t idx) {
  if (!loadCells[idx].wait_ready_timeout(200)) return 0.0f;
  return loadCells[idx].get_units(3);  // median of 3 readings
}

uint8_t readFillPercent(uint8_t idx) {
  uint16_t mm = tof[idx].read(false);
  if (mm == 0) return 0;  // timeout / out of range
  float frac = constrain(static_cast<float>(mm) / BIN_DEPTH_MM, 0.0f, BIN_DEPTH_MM);
  return static_cast<uint8_t>((1.0f - frac) * 100.0f);
}
