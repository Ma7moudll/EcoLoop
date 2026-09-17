# EcoLoop — Architecture

A real, end-to-end recycling-donation system. The Flutter app talks to a
FastAPI backend; the backend owns all business rules and point-awarding. A
Python **hardware simulator** behaves exactly like the future ESP32 firmware —
it is the only "fake" thing in the stack, and it is a drop-in for real
hardware.

```
┌──────────────┐   REST (HTTPS)    ┌──────────────────┐  HTTP   ┌───────────────┐
│  Flutter app │ ────────────────▶ │ FastAPI backend  │ ──────▶ │  AI service   │
│  (iOS/Android)│  /session,status │  (uvicorn)        │  /predict  (classifier)│
└──────────────┘                    │  + PostgreSQL     │         └───────────────┘
        ▲                          └──────────────────┘
        │  WebSocket  /ws/deposits/{operation_id}
        │
        │   MQTT (ecoloop/stations/...)
        ▼
┌──────────────────────────────┐
│  MQTT broker (mosquitto)     │
└──────────────────────────────┘
        ▲                              ▲
        │ publish sensor/state/        │ capture_request
        │ deposit_result               │ (command topic)
┌──────────────────────────────┐   ┌──────────────────────────────┐
│  Hardware simulator (ESP32)  │   │  Station camera              │
│  rotary chute · load cell · IR │   │  ──POST /deposit/capture──▶  backend
│  beam · position · machine   │   │  (FINAL classification       │
└──────────────────────────────┘   │   source; phone never snaps) │
                                   └──────────────────────────────┘
```

## The single most important rule

> Points are awarded **only** by the backend when it validates a physical
> `deposit_result` MQTT event. The client can never award points. The
> simulator never declares success — it only reports physics.

The HTTP layer can create and cancel deposit sessions. The **HTTP callback** path
(`POST /deposit/callback/event`) is internet-reachable, so it requires
`X-Station-Key` (same shared secret as the capture endpoint) before it runs the
`DepositService.complete_from_event` pipeline. The primary completion path is
the MQTT `deposit_result` event (broker-internal trust boundary). Both enter
the same transaction.

## Components

| Component | Location | Role |
|---|---|---|
| Flutter app | `mobile/` | UI; always talks to the real backend — no offline/demo fallback, errors surface honestly |
| Shared models | `shared/` | Dart `Prediction`, `Deposit`, `AppUser`, … wire contract |
| Backend | `backend/` | FastAPI, SQLAlchemy 2, Alembic; all business rules |
| AI service | `ai-service/` | standalone classifier over HTTP; `development` or `real` mode; input quality + object-presence gate before classification |
| AI validation | `ai-service/app/tools/` | data collection + model validation pipeline for the station-top camera (see `docs/ai-validation.md`) |
| Hardware simulator | `hardware-simulator/` | the future ESP32, speaking the MQTT contract |
| Infra | `infra/` | docker-compose, mosquitto config, Postgres bootstrap |
| Docs | `docs/` | this repo's operating manual |

## Backend flow (a deposit)

The **FINAL architecture makes the STATION camera the classification source** —
the phone only identifies the station (QR / code / list) and watches status:

1. `POST /api/v1/deposit/session` **without** `ai_prediction_id` → mints
   `OP-YYYYMMDD-NNNNNN` (locked counter) → creates `deposit_session`
   (status `capture`, TTL) → publishes MQTT `capture_request` to the station.
   **No points here.**
2. The station camera uploads its frame: `POST /api/v1/deposit/capture`
   (`X-Station-Key` + multipart `image`/`operation_id`/`station_code`). The
   backend runs the real AI (camera gate → classifier → routing policy) and
   persists the prediction onto the session (`analyzing` while classifying).
   - A rejected frame (`NO_OBJECT` / `LOW_QUALITY` / `CORRUPT_IMAGE`) returns a
     structured `422 {code, error}` and the session returns to `capture` for a
     retake — nothing is routed.
   - Otherwise, per the confidence policy, the backend publishes the MQTT
     `route` command (HIGH auto / MEDIUM manual). **The capture endpoint can
     never award points.**
3. The station (simulator/firmware) executes the deposit: rotates the chute to
   reads the load cell, crosses the IR beam, and publishes a terminal
   `deposit_result` event.
4. Backend MQTT handler calls `DepositService.complete_from_event` which applies
   **every** gate:
   - session exists · not expired · never completed before
   - station matches the session
   - claimed status `confirmed`
   - `actual_position` == routed position
   - weight ≥ `min_deposit_weight_grams` · `weight_stable`
   - `beam_event_seen` · `mechanical_confirmed` · chute at position
5. If all gates pass, one `BEGIN … COMMIT` transaction (in
   `points_transaction.award_points`) inserts the `waste_event`, updates the
   user's points, upserts student + faculty leaderboard rows, and marks the
   session `confirmed`. A failure rolls everything back — no double-spend.

Legacy phone-camera path (for reference): `POST /ai/predict` → then
`POST /deposit/session` with `ai_prediction_id` → routes immediately. Both
session paths converge on the identical validation pipeline below; awarding
points is impossible through either HTTP entry point.

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
sweeps the database. It asserts 38 checks across 8 deposit scenarios —
including the FINAL station-camera path (session created capture-first, the
harness standing in for the station camera uploads a real frame to
`/deposit/capture`, the backend runs the real AI and routes automatically
before the physical drop) — with exactly 3 paid events, no duplicate awards,
expired/cancelled/rejected award 0, WS auth gate 4401, medium-conf manual
routing never awards points, and the AI input gate rejecting a synthetic grey
frame. Running it against real Postgres also surfaced and fixed two dialect
bugs that SQLite-only tests could not: aware-vs-naive datetime handling and a
`numpy.float32` confidence serialization crash.

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
  (`model: "development"` → backend `source: "demo"`, and the app only then
  shows the demo indicator). It is never reachable from a `real` run; the
  production default is `real`. Its `DEVELOPMENT_FORCE_*` knobs are never read
  by the real classifier; a dedicated test proves production inference is
  identical with and without them, and the E2E starts the real service with
  poison values set to prove the same over the wire.

## Production hardening

- **Config guard.** `validate_production()` runs at backend startup and REFUSES
  to boot in production mode with default/dev secrets, `DEBUG_IMAGE_HASH=true`,
  anonymous MQTT, or TLS disabled (`test_hardening_config.py`).
- **Real health.** `/health` checks Postgres, MQTT connectivity, and ai-service,
  returning `ok`/`degraded` per dependency — never a hardcoded ok.
- **MQTT security.** Broker runs `allow_anonymous false` with per-identity ACLs
  (`infra/mosquitto/acl`): the backend owns the station tree; each station may
  only read its own command topic and write its own telemetry topics. Gateway
  and simulator use TLS (system trust store) for HiveMQ Cloud. Credentials come
  from the environment only. A broker-level integration matrix proves: wrong
  password refused, anonymous refused, cross-station publish never propagates,
  malformed/forged/replayed/reordered events cannot award points
  (`backend/tests/integration/test_mqtt_security_matrix.py`).
- **Rate limiting.** Login 5/min/IP, register 10/min/IP (`test_hardening_auth.py`).
- **Token hygiene.** JWTs carry a `jti`; logout revokes it server-side; every
  request re-checks revocation (`app/security/revocation.py`).
- **Account recovery.** Password reset + email verification use hashed one-time
  tokens with expiry; forgot-password always answers generically.
- **Uploads.** Capture endpoint enforces a size cap (413 beyond it) and content
  validation before the image ever reaches the AI.
- **Rewards once.** Challenge completion is a unique `(user, challenge)` row —
  the reward can never be double-collected (`test_hardening_challenges.py`).
- **WebSocket ownership.** Only the deposit owner (or an admin) may subscribe;
  violations get 4403, invalid tokens 4401 (`test_hardening_ws.py`).
- **Admin surface.** Admin-only endpoints sit behind `require_admin`
  (`test_admin.py`); list endpoints paginate with `limit<=100` + total
  (`test_pagination.py`).
- **Mobile transport.** Android cleartext is allowed ONLY in debug builds
  (emulator → 10.0.2.2); release builds forbid cleartext. iOS declares camera
  usage. The app never holds MQTT credentials.
- **Deployment.** `infra/docker-compose.yml` requires secrets from the env
  (`${VAR:?}` interpolation fails fast), binds only 127.0.0.1 on the host,
  adds healthchecks, restart policies, and memory limits.
