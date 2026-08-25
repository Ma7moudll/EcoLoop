# EcoLoop Station — Mechanism Abstraction (Carriage V1 / Rotary V2)

> **One product. One domain model. One backend authority. One AI pipeline.
> Two interchangeable physical sorting mechanisms.**

Carriage (V1) and Rotary (V2) are **hardware implementations** of the same
station-level software contract. They are NOT two products, and nothing in
the student experience or the shared domain depends on which one is bolted
into the cabinet.

## The contract every mechanism implements

A station unit, regardless of mechanism:

1. **Receives intent** on `ecoloop/stations/{code}/command`:
   `{"command": "route", "operation_id": "OP-…",
     "destination_position": 2, "mode": "automatic|manual"}`
   plus `{"command": "capture_request", "operation_id": "OP-…"}`.
2. **Executes it mechanically** (implementation detail):
   - *V1 carriage*: determine target position → move carriage → detect
     arrival → release waste.
   - *V2 rotary*: determine target angle → rotate chute → detect home/target
     position → release waste.
3. **Reports physics, never success**: machine states and a terminal
   `deposit_result` event (`actual_position`, `mechanism_position`
   [or legacy `carriage_position`], `weight_grams`, `weight_stable`,
   `beam_event_seen`, `mechanical_confirmed`).
4. The **backend independently validates** the physics and — only then —
   awards points in one transaction.

## Where each concept lives

| Concept | Location | Mechanism-aware? |
|---|---|---|
| Route command (compartment intent) | backend MQTT publisher | NO |
| Deposit validation (position/weight/beam) | backend `deposit_service` | NO (accepts neutral + V1 field names) |
| Station registry telemetry | `station_registry` (internal) + neutralized wire (`mechanism_position`) | internal only |
| Mechanical execution | per-mechanism firmware / simulator | YES — isolated here |
| Student app vocabulary | Ecolamp screens | NEVER |

## Rules enforced by audit

- `carriage|stepper|iris|motor|servo|pusher` must not appear in: student
  domain models, points logic, history, rewards, leaderboard, generic deposit
  API, generic station UI. (Verified — see final report.)
- A new mechanism ships by implementing the command/event contract in its
  controller; no backend, shared-model, or student-app change is required.

## Adding Rotary V2 (future phase)

1. Implement `RotaryStationController` firmware speaking this exact contract
   (commands in, states/events out, `mechanism_position` reported).
2. Register the station with `mechanism = "rotary"` in the DB.
3. Nothing else. The backend routes by compartment index; validation is
   already mechanism-neutral.
