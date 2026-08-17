# Recycle Vision — Architecture

A real, end-to-end recycling-donation system. The Flutter app talks to a
FastAPI backend; the backend owns all business rules and point-awarding. A
Python **hardware simulator** behaves exactly like the future ESP32 firmware —
it is the only "fake" thing in the stack, and it is a drop-in for real
hardware.

```
┌──────────────┐   REST (HTTPS)    ┌──────────────────┐  HTTP   ┌───────────────┐
│  Flutter app │ ────────────────▶ │ FastAPI backend  │ ──────▶ │  AI service   │
│  (iOS/Android)│                    │  (uvicorn)        │   /predict  (classifier)│
└──────────────┘                    │  + PostgreSQL     │         └───────────────┘
        ▲                          └──────────────────┘
        │  WebSocket  /ws/deposits/{operation_id}
        │
        │   MQTT (ecoloop/stations/...)
        ▼
┌──────────────────────────────┐
│  MQTT broker (mosquitto)     │
└──────────────────────────────┘
        ▲
        │ publish sensor / state / deposit_result
        │ subscribe .../command
┌──────────────────────────────┐
│  Hardware simulator (ESP32)  │   ← becomes real firmware, unchanged contract
│  carriage · load cell · IR   │
│  beam · position · machine   │
└──────────────────────────────┘
```

## The single most important rule

> Points are awarded **only** by the backend when it validates a physical
> `deposit_result` MQTT event. The client can never award points. The
> simulator never declares success — it only reports physics.

The HTTP layer can create and cancel deposit sessions, but `POST
/deposit/session` and `POST /deposit/callback/event` go through the exact same
`DepositService.complete_from_event` pipeline. Both enter the same transaction.

## Components

| Component | Location | Role |
|---|---|---|
| Flutter app | `mobile/` | UI; kept the existing design system; `OFFLINE_MODE` fallback preserved |
| Shared models | `shared/` | Dart `Prediction`, `Deposit`, `AppUser`, … wire contract |
| Backend | `backend/` | FastAPI, SQLAlchemy 2, Alembic; all business rules |
| AI service | `ai-service/` | standalone classifier over HTTP; `development` or `real` mode |
| Hardware simulator | `hardware-simulator/` | the future ESP32, speaking the MQTT contract |
| Infra | `infra/` | docker-compose, mosquitto config, Postgres bootstrap |
| Docs | `docs/` | this repo's operating manual |

## Backend flow (a deposit)

1. `POST /api/v1/ai/predict` (multipart image) → AI service → DB routing policy →
   persisted `ai_predictions` row → wire `Prediction` (with `confidence_level`,
   `destination_position`, `potential_points`, `expires_at`).
2. `POST /api/v1/deposit/session` with `{ai_prediction_id, station_id}` →
   mints `OP-YYYYMMDD-NNNNNN` (locked counter) → creates `deposit_session`
   (status `pending`, TTL) → publishes MQTT `route` command to the station.
   **No points here.**
3. The station (simulator/firmware) executes the deposit: moves the carriage,
   reads the load cell, crosses the IR beam, and publishes a terminal
   `deposit_result` event.
4. Backend MQTT handler calls `DepositService.complete_from_event` which applies
   **every** gate:
   - session exists · not expired · never completed before
   - station matches the session
   - claimed status `confirmed`
   - `actual_position` == routed position
   - weight ≥ `min_deposit_weight_grams` · `weight_stable`
   - `beam_event_seen` · `mechanical_confirmed` · carriage at position
5. If all gates pass, one `BEGIN … COMMIT` transaction (in
   `points_transaction.award_points`) inserts the `waste_event`, updates the
   user's points, upserts student + faculty leaderboard rows, and marks the
   session `confirmed`. A failure rolls everything back — no double-spend.

Rejections still persist an auditable `waste_event` row with `0` points and a
`reject_reason`. Duplicate terminal events for the same operation are ignored
(the second is a `409`), so a deposit can never double-award.

## Live status (WebSocket) — transport only

During the mechanical wait the app shows the machine's *live phase* instead of
a blank spinner. Machine `state_changed` events are persisted onto the deposit
as a monotonic status and pushed to subscribers:

| machine state | persisted deposit status | UI copy |
|---|---|---|
| `ROUTING` | `routing` | Routing the item… |
| `MOVING` | `moving` | Moving to the compartment… |
| `POSITIONED` / `READY_FOR_DEPOSIT` | `ready` | Item in place — starting detection… |
| `DETECTING` | `detecting` | Detecting the item… |
| `MEASURING` | `measuring` | Measuring weight… |
| terminal event | `confirmed` / `rejected` / `expired` / `cancelled` | terminal UI |

`WS /ws/deposits/{operation_id}?token=<jwt>` fan-out frames are `{"type":
"subscribed"|"state"|"terminal"|"keepalive", …}`. The `deposit` in every frame
is the **authoritative PostgreSQL-backed serialization**, never a raw machine
claim. The WebSocket is strictly a transport optimization: it can never award
points (the backend has no such path), and the Flutter client transparently
falls back to the original HTTP polling whenever the socket is unavailable or
a token is missing. Either path converges on the identical terminal `Deposit`.

## End-to-end proof

`scripts/e2e_real_chain.py` starts the **real** mosquitto broker, the real
ai-service, the real backend on **PostgreSQL**, and an in-process simulator
plus a real WebSocket client, then runs every scenario over HTTP+MQTT+WS and
sweeps the database. It asserts 30 checks (exactly 2 paid events, no duplicate
awards, expired/cancelled/rejected award 0, WS auth gate 4401, medium-conf
manual routing never awards points). Running it against real Postgres also
surfaced and fixed two dialect bugs that SQLite-only tests could not: aware-vs-
naive datetime handling and a `numpy.float32` confidence serialization crash.

## Confidence policy (backend-enforced)

| confidence | level | behavior |
|---|---|---|
| ≥ 0.80 | high | auto-route; session creatable |
| ≥ 0.50 | medium | session creatable, routing mode `manual` |
| < 0.50 | low | cannot route — "please retake the photo" |

## Waste classes → routing

| class | compartment | points |
|---|---|---|
| plastic | 1 | 5 |
| metal | 2 | 10 |
| paper | 3 | 5 |
| other | 4 | 0 |

Driven by the `routing_policy` DB table, not hardcoded.

## Honesty about the model

- `ai-service` serves a **trained** MobileNetV3-Small ONNX artifact
  (`AI_SERVICE_CLASSIFIER=real`, the default) — see `ai-service/reports/
  eval_report.md` for dataset, metrics, confusion matrix and limitations.
- `RealInferenceClassifier` raises `ModelNotReadyError` if the artifact is
  missing — the system never pretends an untrained model works.
- `DevelopmentClassifier` (`AI_SERVICE_CLASSIFIER=development`) is an
  **explicitly isolated test fixture** — a clearly labeled heuristic
  (`model: "development"` → backend `source: "demo"` → the UI's subtle DEMO
  badge). Its `DEVELOPMENT_FORCE_*` knobs are never read by the real
  classifier; a dedicated test proves production inference is identical with
  and without them, and the E2E starts the real service with poison values set
  to prove the same over the wire.
