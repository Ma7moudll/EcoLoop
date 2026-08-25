# Recycle Vision

**Recycle Vision — automated campus waste sorting powered by the Rotary
Sorting Mechanism V2.**

A standalone product: a rotary-chute sorting station, its ESP32 firmware,
an AI classification pipeline, a FastAPI/PostgreSQL backend, an MQTT station
network, simulators, tests and end-to-end proofs — everything needed to run
and demonstrate Recycle Vision on its own.

```
             RECYCLE VISION  (this repository)
   ┌──────────────┼──────────────────┐
   │              │                  │
 mobile         FastAPI +        AI service
 (student app)  PostgreSQL       (station camera → classify → route)
        └──────────┬──────────────────┘
                   │ MQTT (ecoloop/stations/#)
                   ▼
       ROTARY V2 Station (firmware + simulator)
```

## The Rotary Sorting Mechanism V2

Four fixed bins; the moving element is a **rotating chute** that aligns its
outlet with the routed bin:

```
ROUTE_TO compartment → look up target angle (calibration table)
→ rotate stepper shortest path → Hall-sensor home reference
→ position confirmed → gravity release → load cell + IR verification
→ deposit_result (mechanism_position) → backend awards points
```

Engineering notes, geometry, torque budget, wiring, BOM, calibration and
recovery procedures: `docs/rotary-v2.md`. The carriage-era simulator is kept
under `hardware-simulator/` strictly as a legacy reference; the product's
mechanism is Rotary V2.

## Layout

| Path | What |
|---|---|
| `backend/` | FastAPI + SQLAlchemy + Alembic API (auth, deposits, points authority, rewards, leaderboard) |
| `ai-service/` | quality gate → preprocessing → ONNX classifier → confidence/routing policy |
| `hardware-simulator/` | MQTT-accurate station simulators (`simulator.py` legacy carriage reference, `rotary_simulator.py` = **V2**) |
| `firmware/rotary-v2/` | ESP32 firmware for the rotary station |
| `mobile/` | Flutter student app |
| `shared/` | Dart wire models for the mobile app |
| `scripts/` | `e2e_rotary_chain.py` (Rotary live proof), `e2e_real_chain.py` (legacy harness) |
| `infra/` | docker-compose + authenticated mosquitto config |
| `docs/` | architecture, API contract, MQTT contract, mechanism abstraction |

## Run

```bash
# development broker + services (see docs/architecture.md)
python scripts/e2e_rotary_chain.py     # full-chain Rotary proof on real services
pytest backend/tests ai-service/tests hardware-simulator/tests
pio run -d firmware/rotary-v2          # compiles clean for esp32dev
```

Ports/services are owned by this project (API 8000/8080 · AI 8051 · MQTT
1883/1884) and are configured exclusively via this repository's environment.
