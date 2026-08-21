# Hardware Checklist — EcoLoop Station (FINAL station-camera architecture)

This checklist is the ground truth for what the **hardware** proves today and
what a **physical** station must still prove. The FINAL architecture makes the
STATION camera (`POST /api/v1/deposit/capture`, `X-Station-Key`) the only
classification source; the phone only identifies the station and observes.

Honesty rule: every item is either **PROVEN** (software-simulated, real
services, regression-signed) or **NOT YET PROVEN** (requires physical
hardware). Nothing here is fabricated.

## 1. Software / simulated hardware — PROVEN

Run with real services (mosquitto, ai-service `real` ONNX, FastAPI backend,
PostgreSQL) and the hardware simulator standing in for the ESP32:

| check | proof | status |
|---|---|---|
| Station camera answers `capture_request` with a binary `image` + `operation_id` + `station_code` + `X-Station-Key` | `hardware-simulator/camera.py` `CaptureUploader`; `scripts/e2e_real_chain.py` Scenario I; `scripts/station_capture_e2e_stack.py` | **PROVEN (simulated)** |
| Wrong/missing station key on `/deposit/capture` → `401` | `backend/tests/test_capture.py::test_capture_requires_station_key`, `test_capture_wrong_station_key` | **PROVEN** |
| Backend classifies the frame with the real AI (gate → ONNX → calibration) and auto-routes HIGH | `scripts/e2e_real_chain.py` ("Station capture -> real AI -> route -> confirmed +5", `mode=automatic`) | **PROVEN (simulated)** |
| Low-confidence frame / gate rejection → session returns to `capture`, no route, no points | `backend/tests/test_capture.py` (gate rejection + capture retake), E2E Scenario G | **PROVEN** |
| AI service unavailable → structured `503 AI_UNAVAILABLE`, session returns to `capture`, no stuck `analyzing`, no points | `backend/tests/test_capture.py::test_capture_ai_service_unavailable_503_and_capture_retake` | **PROVEN** |
| Physical drop (carriage → load cell → IR beam → mechanical) reported as `deposit_result` over MQTT | `hardware-simulator/simulator.py::run_plan` + `scenarios.py` | **PROVEN (simulated)** |
| Backend validates every gate and awards points only once, in one transaction | `scripts/e2e_real_chain.py` (Scenarios A–I, duplicate, expired, wrong-position, underweight); final DB sweep (3 confirmed / 3 paid / 60 pts) | **PROVEN (simulated)** |
| HTTP cannot award points: unauthenticated callback rejected `401` | `backend/tests/test_capture.py::test_callback_without_station_key_cannot_award_points`, `test_callback_wrong_station_key_rejected` | **PROVEN** |
| Full-stack health incl. real AI round-trip | `scripts/dev_health.sh` → 5/5 (Postgres, mosquitto, ai real, backend, prediction `source=ai`) | **PROVEN** |

## 2. Physical station hardware — NOT YET PROVEN

Requires a real station unit (ESP32 + carriage + load cell + IR beam + top
camera) attached to the same broker/backend. The procedure below is the
spec; results must be recorded in a template explicitly marked BLOCKED until a
device is attached.

### 2.1 Fixture / wiring checklist (build phase)

- [ ] ESP32 (or ESP32-CAM) boots, connects to Wi-Fi, publishes heartbeat on
      `ecoloop/stations/{code}/heartbeat`.
- [ ] Firmware subscribes to `ecoloop/stations/{code}/command` (QoS 1).
- [ ] Camera module powers on and captures at least one 640×480 JPEG the
      gate/classifier accepts (gate = good lighting, no blur, object present).
- [ ] `X-Station-Key` configured in firmware == backend `STATION_API_KEY`.
- [ ] Carriage reaches each of the 4 positions under `route` command without
      stall; position sensor agrees.
- [ ] Load cell settles; `weight_stable` true at ≥ `MIN_DEPOSIT_WEIGHT_GRAMS`.
- [ ] IR beam breaks on item pass and clears after; `beam_event_seen` true.
- [ ] Mechanical-confirmation switch/flag reports `mechanical_confirmed=true`.

### 2.2 End-to-end physical validation (validation phase)

Run the full soft stack (see `scripts/station_capture_e2e_stack.py`), then:

1. Create a capture-first session from the phone (QR/station code) → backend
   publishes `capture_request` over MQTT.
2. Camera snaps a REAL object, uploads to `/api/v1/deposit/capture` with the
   station key → backend classifies with the real ONNX model → `route` command
   published (HIGH auto / MEDIUM manual).
3. Firmware executes the physical drop → `deposit_result` published → backend
   validates position/weight/beam/mechanical → confirmed +points.
4. Repeat for: plastic, metal, paper, other; a wrong-position drop (→
   `rejected`), a sub-minimum weight (→ `rejected`), an expired session (→
   `expired`), a duplicate terminal (→ `409`).

### 2.3 Checks to record (results template — start BLOCKED)

- Frame hash matches on-device vs backend (`debug/image-sha256`, gated by
  `DEBUG_IMAGE_HASH=true`).
- Classification, confidence, confidence_level, mode (auto/manual).
- Route destination vs `actual_position` agreement.
- Weight reading at settle; stability flag; beam event; mechanical flag.
- Correct point award per deposit; point delta === `potential_points`; state
  machine progression capture → analyzing → routing → moving → ready →
  detecting → measuring → confirmed/reset; rejection reasons verbatim.

Real station-camera accuracy is Tier C in `docs/ai-validation.md` — **not yet
established**, and this checklist does not claim it.