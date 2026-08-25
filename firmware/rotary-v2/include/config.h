// =============================================================================
// EcoLoop Station V2 — Rotary Sorting Mechanism :: configuration
//
// EVERY hardware-specific value lives here (§23). The state machine and
// controllers contain zero magic numbers. Recalibration = edit this file
// (or use serial calibration mode) — never the logic.
// =============================================================================
#pragma once

// ---------------------------------------------------------------- identity --
static const char* STATION_CODE      = "ST-001";
static const char* STATION_MECHANISM = "rotary";   // never "carriage" on V2

// ------------------------------------------------------------------- WiFi ---
static const char* WIFI_SSID         = "ecoloop-station";
static const char* WIFI_PASS         = "change-me";
static const char* MQTT_HOST         = "192.168.1.10";
static const uint16_t MQTT_PORT      = 1883;
static const char* MQTT_USER         = "station-" ;   // + STATION_CODE at runtime
static const char* MQTT_PASS         = "change-me";
static const char* MQTT_TOPIC_PREFIX = "ecoloop/stations";

// ------------------------------------------------------------- stepper ------
static const int   PIN_STEP          = 25;
static const int   PIN_DIR           = 26;
static const int   PIN_ENABLE        = 27;   // LOW = enabled (TMC2209)
static const float STEPPER_STEPS_REV = 200.0;  // 1.8° NEMA 17
static const int   MICROSTEPPING     = 16;         // TMC2209 config
static const float GEAR_RATIO        = 1.0;        // direct drive
static const float MAX_DEG_PER_SEC   = 300.0;      // slew limit (torque budget)
static const float ACCEL_DEG_PER_S2  = 1000.0;     // within torque calc margin

// ---------------------------------------------------------------- homing ----
static const int   PIN_HOME_HALL     = 34;   // digital Hall, active LOW w/ pullup
static const bool  HOME_SEEK_DIR_CCW = true; // rotate CCW onto hard stop
static const float HOME_BACKOFF_DEG  = 3.0;  // settle onto exact reference
static const float HOMING_TIMEOUT_S  = 12.0;
static const float MOVE_TIMEOUT_S    = 6.0;  // §11/§25: never stall indefinitely

// --------------------------------------------------------------- load cells -
// 4x HX711 sharing one SCK line (each has its own DOUT). Per-bin calibration
// factors from `CAL` serial mode.
static const int   PIN_HX_SCK        = 32;
static const int   PIN_HX_DOUT[4]    = {33, 35, 36, 39};  // P,M,Pp,O order
static const float LC_CALIBRATION[4] = { 402.6f, 398.1f, 405.0f, 400.3f }; // units/kg
static const float MIN_DEPOSIT_G     = 1.0;   // must match backend MIN_DEPOSIT_WEIGHT_GRAMS
static const float WEIGHT_SETTLE_S   = 1.5;

// ------------------------------------------------------------ fill sensors --
// VL53L1X ToF, one per bin; XSHUT used to assign distinct I2C addresses.
static const int   PIN_TOF_XSHUT[4]  = { 4, 13, 14, 15 };
static const uint8_t TOF_ADDR[4]     = { 0x2A, 0x2B, 0x2C, 0x2D };
static const float BIN_DEPTH_MM      = 250.0;
static const float FILL_NEAR_FULL_PCT = 75.0;
static const float FILL_FULL_PCT      = 95.0;

// ----------------------------------------------------------------- timing ---
static const uint32_t HEARTBEAT_MS   = 5000;
static const uint32_t MQTT_LWT_GRACE = 15;    // seconds, broker-side

// --------------------------------------------------------- safety limits ----
static const float MAX_WASTE_KG_PER_BIN = 2.0;   // overload guard
