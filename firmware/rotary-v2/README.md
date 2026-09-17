# EcoLoop Station V2 — Rotary firmware (ESP32)

Firmware for the Rotary Sorting Mechanism V2. Implements the existing
EcoLoop station MQTT contract (`../../docs/mqtt-contract.md`) and
reports the mechanism-neutral `mechanism_position` field.

## Build

```bash
pio run                 # compiles for esp32dev
pio run -t upload       # flash over USB
pio device monitor      # 115200 baud console
```

Status: **compiles clean** (31 % flash, 8 % RAM on esp32dev).

## Layers

```
src/mqtt_station.cpp   topics, JSON, reconnect + LWT, command idempotency (§21)
src/station_fsm.cpp    shared deposit lifecycle (identical to Carriage V1)
src/rotary_controller.cpp  homing, shortest-path motion, watchdogs, e-stop
src/bin_map.cpp        THE calibration layer — bins -> angles -> steps
include/config.h       every hardware constant; no magic numbers elsewhere
src/main.cpp           non-blocking loop, operation engine, safe-state logic
```

## Safety behaviors (§11, §20, §25)

- move refused if it cannot finish inside `MOVE_TIMEOUT_S` at max slew
- progress watchdog: no step progress → JAMMED, driver disabled
- homing seek capped at 450° → TIMEOUT, never endless seek
- MQTT loss mid-motion → immediate `emergencyStop()` + broker LWT offline
- duplicate route for a running `operation_id` ignored

## Calibration mode (§24)

Send `CAL\n` within 5 s of boot while holding BOOT. Commands:
`home`, `cw <deg>`, `ccw <deg>`, `zero`, `goto <pos>`, `sensors`, `load`, `pos`, `quit`.

See `../../docs/rotary-v2.md` for the mechanical design, wiring, BOM,
torque budget, calibration and jam-recovery procedures.
