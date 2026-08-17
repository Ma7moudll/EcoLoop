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
{"id": "u-demo", "studentCode": "S-DEMO1", "name": "Demo Student",
 "facultyId": "engineering", "facultyName": "Faculty of Engineering",
 "points": 45}
```

## AI

`POST /ai/predict` — multipart field `image` (jpeg/png).

```json
{"prediction_id": "pred-abc…", "operation_id": "OP-PRED-…",
 "predicted_class": "plastic", "confidence": 0.95,
 "confidence_level": "high", "recyclable": true,
 "destination_position": 1, "potential_points": 5,
 "expires_at": "…", "source": "demo|ai"}
```

## Deposits

| Method | Path | Body | Notes |
|---|---|---|---|
| POST | `/deposit/session` | `{ai_prediction_id, station_id}` | mints `OP-YYYYMMDD-NNNNNN`, publishes MQTT route; **never awards points** |
| GET | `/deposit/{operation_id}` | — | live status (polling path) |
| POST | `/deposit/{operation_id}/cancel` | — | allowed during any live phase (`pending`…`measuring`); blocked once terminal |
| POST | `/deposit/callback/event` | `CallbackEvent` | HTTP parity path for hardware events |

Deposit wire shape — `status` is `pending`, a live phase (`routing`, `moving`,
`ready`, `detecting`, `measuring`), or a terminal outcome (`confirmed`,
`rejected`, `cancelled`, `expired`):

```json
{"operation_id": "OP-20260817-000001", "prediction_id": "pred-…",
 "station_id": "st-001", "predicted_class": "plastic",
 "expected_position": 1, "actual_position": 1, "weight_g": 18.4,
 "mechanical_confirmed": true, "potential_points": 5,
 "points_awarded": 5, "status": "confirmed", "expires_at": "…",
 "reject_reason": null}
```

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
