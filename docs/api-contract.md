# API Contract (v1)

Base URL: `http://<host>:8000` · prefix `/api/v1`. Auth: `Authorization:
Bearer <jwt>` for everything except `register`/`login`. CORS: open (dev).

All timestamps are ISO-8601 strings.

## Auth

| Method | Path | Body / form | Success |
|---|---|---|---|
| POST | `/auth/register` | `{name, email, studentCode?, facultyId, password}` | `{token, user}` |
| POST | `/auth/login` | `{email, password}` | `{token, user}` |
| POST | `/auth/logout` | — | `{status: "logged_out"}` |
| GET | `/auth/me` | — | `{user}` |

`user` shape (also returned by `GET /users/me`):

```json
{"id": "u-abc…", "studentCode": "S-2026-…", "name": "Sara Ali",
 "facultyId": "engineering", "facultyName": "Faculty of Engineering",
 "points": 0}
```

## AI

`POST /ai/predict` — multipart field `image` (jpeg/png).

```json
{"prediction_id": "pred-abc…", "operation_id": "OP-PRED-…",
 "predicted_class": "plastic", "confidence": 0.95,
 "confidence_level": "high", "recyclable": true,
 "destination_position": 1, "potential_points": 5,
 "expires_at": "…", "source": "ai"}
```

`source` is `"ai"` whenever a real trained model ran; `"demo"` only when the
backend explicitly served a development-fixture prediction (a clearly isolated
test-only classifier — never the default).

## Deposits

| Method | Path | Body | Notes |
|---|---|---|---|
| POST | `/deposit/session` | `{ai_prediction_id?, station_id}` | **FINAL station-camera path:** omit `ai_prediction_id` → session is created capture-first (`status=capture`) and the backend publishes an MQTT `capture_request` so the STATION camera snaps the frame. Legacy phone-camera path (`ai_prediction_id` set) routes immediately. **Never awards points** |
| POST | `/deposit/capture` | multipart: `image`, `operation_id`, `station_code` + header `X-Station-Key` | the station camera uploads the frame; backend runs the real `PredictService`, attaches prediction + confidence, auto-routes (HIGH auto / MEDIUM manual / LOW rejected). **This endpoint can never award points** — only physical MQTT `deposit_result` can |
| GET | `/deposit/{operation_id}` | — | live status (polling path) |
| POST | `/deposit/{operation_id}/cancel` | — | allowed during any live phase (`capture`…`measuring`); blocked once terminal |
| POST | `/deposit/callback/event` | `CallbackEvent` + header `X-Station-Key` | HTTP parity path for hardware events; **requires the same station key as `/deposit/capture`** so a random caller cannot fabricate a `deposit_result` and award themselves points (MQTT remains the primary path, broker-internal) |

Deposit wire shape — `status` is `capture`/`analyzing` (station-camera capture
phase), `pending`, a live phase (`routing`, `moving`, `ready`, `detecting`,
`measuring`), or a terminal outcome (`confirmed`, `rejected`, `cancelled`,
`expired`):

```json
{"operation_id": "OP-20260817-000001", "prediction_id": "",
 "station_id": "st-001", "predicted_class": "plastic",
 "expected_position": 1, "confidence": 0.93, "confidence_level": "high",
 "actual_position": 1, "weight_g": 18.4,
 "mechanical_confirmed": true, "potential_points": 5,
 "points_awarded": 5, "status": "confirmed", "expires_at": "…",
 "reject_reason": null}
```

`prediction_id` is empty until the station camera uploads a frame; `confidence`
/ `confidence_level` are only populated once the backend classifies the frame.

### Capture flow (station camera)

1. `POST /deposit/session` **without** `ai_prediction_id` → `{status: "capture", operation_id}`; the backend publishes `capture_request` over MQTT.
2. The STATION camera uploads its frame: `POST /deposit/capture` with `X-Station-Key: <key>` (401 if missing/wrong), multipart `image` + `operation_id` + `station_code` (422 if unknown/mismatched station or unknown operation).
3. The backend classifies via the real AI and updates the session to `analyzing` → `routing`/`moving`/… A rejected input frame returns `422 {code, error}` (e.g. `NO_OBJECT`, `LOW_QUALITY`, `CORRUPT_IMAGE`) and the session returns to `capture` for a retake. If the AI service is unreachable/errored, the endpoint returns `503 {code: "AI_UNAVAILABLE", error}` and the session also returns to `capture` (never stuck in `analyzing`, never a 500 leak).
4. Physical completion still requires the MQTT `deposit_result` event → `confirmed` + points.

`CallbackEvent` (the MQTT `deposit_result` payload):

```json
{"station_id": "ST-001", "operation_id": "OP-…", "event": "deposit_result",
 "status": "confirmed", "actual_position": 1, "carriage_position": 1,
 "weight_grams": 18.4, "weight_stable": true, "beam_event_seen": true,
 "mechanical_confirmed": true, "reason": null}
```

## User data

| Method | Path | Success |
|---|---|---|
| GET | `/users/me` | `{user}` |
| GET | `/impact` | `{total_points, recycled_kg, items_recycled, co2_saved_kg, breakdown[]}` |
| GET | `/waste/history` | `{items:[{id, operation_id, station_id, predicted_class, weight_g, points_awarded, created_at}]}` |
| GET | `/waste/history/{id}` | `{item}` |
| GET | `/leaderboard?scope=students\|faculties` | `{entries:[{id,name,detail,points}]}` |
| GET | `/leaderboard/students` · `/leaderboard/faculties` | `{entries}` |
| GET | `/challenges` | `{items}` |

## Stations

| Method | Path | Success |
|---|---|---|
| GET | `/stations` | `{items:[station]}` (live registry + compartment readiness) |
| GET | `/stations/{id}` | one station |
| GET | `/stations/{id}/status` | live snapshot |

## Real-time

`WS /ws/deposits/{operation_id}?token=<jwt>` — WebSocket clients can't set
headers, so auth is a JWT in the query string. A missing/invalid token is
closed with code `4401`. Frames:

| type | payload | meaning |
|---|---|---|
| `subscribed` | `{operation_id}` | connection accepted, waiting for events |
| `state` | `{deposit}` | live phase persisted from a machine `state_changed` |
| `terminal` | `{deposit}` | final outcome (confirmed/rejected/cancelled/expired) |
| `keepalive` | — | heartbeat every 25s during long waits |

Every `deposit` is the authoritative backend serialization — the socket is
transport only and can never award points. Clients should treat the socket as
an optimization and fall back to `GET /deposit/{operation_id}` polling.

## Errors

- `401` missing/invalid token
- `409` duplicate email / duplicate deposit event
- `404` unknown operation/station
- `422` validation failure (incl. low-confidence routing, expired prediction)
- `503` AI service unreachable / model not ready
