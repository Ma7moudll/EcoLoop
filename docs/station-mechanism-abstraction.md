# EcoLoop Station — Mechanical Abstraction (Rotary V2)

> **One product. One domain model. One backend authority. One AI pipeline.
> One physical sorting mechanism: the Rotary V2 chute.**

The station-level software contract is deliberately mechanism-agnostic. The
rotating chute is a hardware implementation detail: nothing in the student
experience or the shared domain depends on how the unit moves the waste.

## The contract the mechanism implements

A station unit:

1. **Receives intent** on `ecoloop/stations/{code}/command`:
   `{"command": "route", "operation_id": "OP-…",
     "destination_position": 2, "mode": "automatic|manual"}`
   plus `{"command": "capture_request", "operation_id": "OP-…"}`.
2. **Executes it mechanically** (implementation detail): determine target
   angle from the BinMap calibration table → rotate the chute shortest path
   → Hall-sensor home reference → position confirmed → gravity release.
3. **Reports physics, never success**: machine states and a terminal
   `deposit_result` event (`actual_position`, `mechanism_position`,
   `weight_grams`, `weight_stable`, `beam_event_seen`,
   `mechanical_confirmed`).
4. The **backend independently validates** the physics and — only then —
   awards points in one transaction.

## Where each concept lives

| Concept | Location | Mechanism-aware? |
|---|---|---|
| Route command (compartment intent) | backend MQTT publisher | NO |
| Deposit validation (position/weight/beam) | backend `deposit_service` | NO |
| Station registry telemetry | `station_registry` (internal) + abstract wire (`mechanism_position`) | internal only |
| Mechanical execution | firmware / simulator | YES — isolated here |
| Student app vocabulary | EcoLoop screens | NEVER |

## Rules enforced by audit

- `chute|stepper|motor|servo|hall|rotation` vocabulary must not appear in:
  student domain models, points logic, history, rewards, leaderboard, generic
  deposit API, generic station UI.
- The wire carries only abstract fields (`mechanism_position`), so the
  backend and the student app never see mechanical details.
