# Hardware Protocol & Simulator

## What is simulated

Only the **hardware itself** is simulated. Everything else — MQTT, the broker,
the backend, Postgres, the AI service, points — is real. The simulator is the
future ESP32 firmware: it subscribes to `…/{code}/command`, drives (simulated)
actuators/sensors, and publishes the documented telemetry. Replacing it with
real firmware requires **zero backend changes**.

Components in `hardware-simulator/`:

| Module | What it models |
|---|---|
| `config.py` | env-driven physical parameters (movement time, noise, thresholds) |
| `hardware/carriage.py` | carriage that moves position-by-position; configurable jam |
| `hardware/load_cell.py` | HX711-like load cell; deterministic settle profile + gaussian noise |
| `hardware/sensors.py` | IR beam, position and door sensors |
| `hardware/state_machine.py` | strict transition table (`IllegalTransition` on invalid moves) |
| `hardware/station.py` | one station unit (motor + sensors + machine) |
| `scenarios.py` | 6 deterministic deposit plans (see mqtt-contract) |
| `mqtt_client.py` | paho wrapper, protocol-identical to ESP32 code |
| `simulator.py` | runtime + CLI that turns a plan into published telemetry |

The load cell settle profile is a piecewise ADC trace:
`0.0s → 0g, 0.8s → 4g, 1.4s → 12g, 2.0s → 18.4g (stable)`.

## Running it

Requires a broker on `localhost:1883` (see `infra/` or `brew install mosquitto
&& mosquitto`).

```bash
cd hardware-simulator

# Act like the ESP32: connect, subscribe, wait for backend commands.
python simulator.py

# One-shot scenario against the broker, then exit.
SIMULATOR_RAMP_STEP=0 python simulator.py --scenario valid-plastic
```

Env knobs: `MQTT_BROKER_HOST/PORT`, `MQTT_USERNAME/PASSWORD`, `STATION_ID`,
`STATION_CODE`, `SIMULATOR_MOVEMENT_TIME`, `SIMULATOR_SENSOR_NOISE`,
`MIN_DEPOSIT_WEIGHT_GRAMS`, `SIMULATOR_RAMP_STEP` (set `0` for instant ramps).

## Running the whole stack

Without Docker (current dev default) — use the one-command launcher:

```bash
scripts/dev_up.sh        # local Postgres + mosquitto :1884 + ai-service :8051 (real ONNX) + backend :8080 (no demo user)
scripts/dev_health.sh    # 5 health checks incl. a real AI round-trip
```

Manual equivalent (legacy, SQLite/Postgres — see `scripts/dev_up.sh` for the
real production-shaped stack):

With Docker (daemon running):

```bash
docker compose -f infra/docker-compose.yml up --build
# optional in-container simulator:
docker compose -f infra/docker-compose.yml --profile simulator up simulator
```

## Standing end-to-end proof

`scripts/e2e_real_chain.py` runs the entire chain against **real services**
(no TestClient): a spawned mosquitto on 1884, the ai-service on 8051 **serving
the trained ONNX model**, the backend on 8080 wired to a real PostgreSQL
database, an in-process simulator acting as the ESP32 + STATION camera, and a
real WebSocket client. It drives the valid deposit plus wrong-position,
underweight, expired, cancelled, duplicate-terminal, gate-rejected,
medium-confidence and **Scenario I (station-camera capture-first path)** over
HTTP+MQTT+WS, then sweeps the database (exactly 3 paid events, no duplicate
rows, rejected/expired/cancelled award 0, final balance 45+5+5+5=60). The
confidence scenarios use **real model scores** on curated fixture images — the
ai-service is started with `DEVELOPMENT_FORCE_*` poison values to prove the
production path ignores them. Requires local PostgreSQL (`recycle`/`recycle`,
database `recycle_vision_e2e`, schema at alembic head) and free ports
1884/8051/8080.

```bash
.venv/bin/python scripts/e2e_real_chain.py
# RESULT: 37 passed, 0 failed
```

## Tests

```bash
cd backend && PYTHONPATH=. .venv/bin/python -m pytest tests -q     # 79 tests
cd hardware-simulator && SIMULATOR_RAMP_STEP=0 .venv/bin/python -m pytest tests -q  # 30
cd ai-service && PYTHONPATH=. .venv/bin/python -m pytest tests -q  # 82 (incl. pipeline + real-model security)
cd mobile && flutter test                                          # 29 widget/unit (analyze clean)
```

The ai-service suite now includes the data-collection / model-validation
pipeline regressions (`tests/test_tools.py` — leakage-free split, metadata
uniqueness, duplicate detection, augmentation contract, calibration
determinism) and the real-model open-set tests (`tests/test_real_security.py`).
See `docs/ai-validation.md` for the pipeline itself.

The integration tests in `backend/tests/integration` spawn a real mosquitto and
drive the whole chain: predict → session → MQTT route command → simulator
physics → backend validation → points in Postgres/SQLite. The backend capture
suite (`backend/tests/test_capture.py`) proves the FINAL station-camera path:
capture-first session, `capture_request`, station-key-gated capture (401 on
missing/wrong key), gate-rejection retake, AI-outage 503 retake, station
mismatch, and the physical-event completion that still gates all points. The
mobile suite covers the WebSocket live-phase rendering, the polling fallback,
and every terminal outcome.

## AI data collection & model validation

The station-top camera feed is prepared and validated with the tools under
`ai-service/app/tools/` (collection, dataset quality, leakage-free split,
calibration, fine-tune comparison, open-set probe). A simulated pilot dataset
stands in until real camera captures exist — provenance is always tagged
`source=simulated-station-pilot`, and coverage of the real station camera is
**not** claimed. See `docs/ai-validation.md`.
