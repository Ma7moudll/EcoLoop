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

Without Docker (current dev default):

```bash
# 1. broker
/opt/homebrew/sbin/mosquitto -c infra/mosquitto/mosquitto.conf

# 2. AI service (venv shared with backend)
PYTHONPATH=ai-service .venv/bin/uvicorn app.main:app --port 8051

# 3. backend (SQLite for zero-dependency, or Postgres)
PYTHONPATH=backend DATABASE_URL=sqlite:///./recycle.db MQTT_BROKER_HOST=localhost \
  .venv/bin/uvicorn app.main:app --port 8000

# 4. simulator
cd hardware-simulator && python simulator.py
```

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
database, an in-process simulator acting as the ESP32, and a real WebSocket
client. It drives the valid deposit plus wrong-position, underweight, expired,
cancelled, duplicate-terminal, low-confidence and medium-confidence scenarios
over HTTP+MQTT+WS, then sweeps the database (exactly 2 paid events, no
duplicate rows, rejected/expired award 0, final balance 45+5+5). The confidence
scenarios use **real model scores** on curated fixture images — the ai-service
is started with `DEVELOPMENT_FORCE_*` poison values to prove the production
path ignores them. Requires local PostgreSQL (`recycle`/`recycle`, database
`recycle_vision_e2e`) and free ports 1884/8051/8080.

```bash
.venv/bin/python scripts/e2e_real_chain.py
# RESULT: 30 passed, 0 failed
```

## Tests

```bash
cd backend && PYTHONPATH=. .venv/bin/python -m pytest tests -q     # 57 tests
cd hardware-simulator && SIMULATOR_RAMP_STEP=0 .venv/bin/python -m pytest tests -q  # 27
cd ai-service && PYTHONPATH=. .venv/bin/python -m pytest tests -q  # 29 tests
cd mobile && flutter test                                          # 27 widget/unit
```

The integration tests in `backend/tests/integration` spawn a real mosquitto and
drive the whole chain: predict → session → MQTT route command → simulator
physics → backend validation → points in Postgres/SQLite. The mobile suite
covers the WebSocket live-phase rendering, the polling fallback, and every
terminal outcome.
