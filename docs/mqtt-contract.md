# MQTT Contract

Prefix: `ecoloop/stations` (configurable via `MQTT_TOPIC_PREFIX`).
A single station = one physical unit with **four internal compartments**
(positions `1..4`), an internal carriage, a load cell and an IR beam.

## Topics

| Topic | Direction | QoS | Payload |
|---|---|---|---|
| `ecoloop/stations/{code}/command` | backend → station | 1 | route command |
| `ecoloop/stations/{code}/state` | station → backend | 1 | machine state changes |
| `ecoloop/stations/{code}/sensor` | station → backend | 1 | sensor telemetry stream |
| `ecoloop/stations/{code}/event` | station → backend | 1 | state_changed + terminal `deposit_result` |
| `ecoloop/stations/{code}/heartbeat` | station → backend | 0 | liveness |

`{code}` is the human station code (`ST-001`).

## Route command (backend → station)

```json
{"command": "route", "operation_id": "OP-20260817-000001",
 "destination_position": 1, "mode": "automatic|manual"}
```

The simulator executes the physical plan and reports what physically happened.
It never echoes the command as "success".

## Capture request (backend → station, FINAL station-camera path)

Sent on the same `command` topic when a session is created **without** an
`ai_prediction_id` (capture-first). The station camera responds by uploading
its frame to `POST /api/v1/deposit/capture`:

```json
{"command": "capture_request", "operation_id": "OP-20260817-000002"}
```

The backend then classifies the frame and, per the confidence policy (HIGH auto
/ MEDIUM manual / LOW rejected), publishes the normal `route` command (or the
gate returns `422 {code, error}` and the session returns to `capture` for a
retake). The phone never snaps a photo — the station camera is the only
classification source.

## Terminal event (station → backend)

Published on `event` with `event: "deposit_result"` — this is the payload the
backend validates:

```json
{"station_id": "ST-001", "operation_id": "OP-…",
 "event": "deposit_result", "status": "confirmed|jam|underweight|timeout|sensor_error",
 "actual_position": 1, "carriage_position": 1,
 "weight_grams": 18.4, "weight_stable": true,
 "beam_event_seen": true, "mechanical_confirmed": true,
 "timestamp": "…"}
```

`status` is the machine's belief. The backend **independently** checks
position, weight, stability, beam, mechanical confirmation and carriage
position — a machine can report `confirmed` and still be rejected (e.g. it
physically landed in compartment 2 while the backend routed to 1).

## Machine states

`IDLE → ROUTING → MOVING → POSITIONED → READY_FOR_DEPOSIT → DETECTING →
MEASURING → DEPOSIT_CONFIRMED → RESETTING → IDLE`

Error states (each → `RESETTING`): `JAMMED`, `WRONG_POSITION`, `UNDERWEIGHT`,
`SENSOR_ERROR`, `TIMEOUT`.

State changes are published as `{"event": "state_changed", "state": "…"}` on
`event`. The backend persists the live phase onto the deposit (`ROUTING→
routing`, `MOVING→moving`, `POSITIONED`/`READY_FOR_DEPOSIT→ready`,
`DETECTING→detecting`, `MEASURING→measuring`) and forwards the authoritative
serialized deposit to the operation's WebSocket subscribers. The transition is
monotonic — a late telemetry frame can never regress the status — and no
state change ever touches points.

## End-to-end deposit sequence

1. `POST /api/v1/deposit/session` — without `ai_prediction_id` the backend
   publishes `capture_request`; the station camera uploads a frame to
   `POST /api/v1/deposit/capture`, the backend runs the real AI, and then
   publishes `route` (automatic or manual). With `ai_prediction_id` (legacy
   path) `route` is published immediately.
2. Simulator: `ROUTING`, `MOVING` (per-step `sensor` telemetry with
   `carriage_position`), `POSITIONED`, `READY_FOR_DEPOSIT`.
3. `DETECTING` (beam breaks), `MEASURING` (weight ramp, `weight_stable` at
   settle), beam clears.
4. `DEPOSIT_CONFIRMED` → `deposit_result` terminal event → backend validates
   and (if valid) awards points in one transaction.
5. `RESETTING` → `IDLE`.

## Scenarios shipped with the simulator

| Scenario | Behavior | Backend outcome |
|---|---|---|
| `valid-plastic` | obey route, 18.4g stable, beam+mech OK | confirmed +5 |
| `wrong-position` | carriage lands at compartment 2 (routed to 1) | rejected `wrong_position` |
| `underweight` | only 0.5g | rejected `underweight` |
| `jam` | carriage jams mid-move | rejected `jam` |
| `timeout` | terminal arrives after session expiry | rejected `expired` |
| `duplicate` | two identical terminals | 1st confirmed, 2nd `409` |
