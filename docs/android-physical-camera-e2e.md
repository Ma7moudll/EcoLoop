# Android physical camera → real AI: validation procedure

Validates the **existing** Android camera → backend → AI gate → real ONNX
model path on a **physical** Android device with **real physical objects**
(plastic / metal / paper / other).

Thick red line: this is **validation, not optimization**. The model, the gate
thresholds, and the classifier confidence thresholds are **not** changed here.

## Provenance & honesty rules (from docs/ai-validation.md)

| evidence tier | status | what it proves |
|---|---|---|
| A — TrashNet benchmark | shipped | model on the academic set it was trained on |
| B — simulated-station-pilot | shipped | pipeline under simulated distribution shift |
| C — real physical Android camera | **not yet** | the remaining gap this procedure targets |

Tier C results are reported **separately**. Never merged with A or B, never
combined into one accuracy number. Small samples are called exactly
“initial physical-camera validation”, never “production validation”.

**Do not use** the emulator virtual scene, fixtures, bundled images, a mocked
camera, mocked HTTP, fake predictions, `OFFLINE_MODE` or `DEMO_MODE`. The app
is built and driven with `OFFLINE_MODE=false`, `DEMO_MODE=false`.

---

## 1. Physical device requirements

- Android phone with a **rear camera** the `camera` plugin can drive (API 21+; a
  modern device is fine — the model is not hardware-specific).
- USB debugging enabled; device authorized.
- An arm64 debug build (default for real phones).
- The back camera must be `android.hardware.camera`. If missing, the app falls
  back to the gallery path (that’s a separate flow, not this validation).

## 2. USB debugging + adb setup

```bash
adb kill-server; adb start-server
adb devices -l
# Physical phone must appear, e.g.:
#   2a7f3c1b       device usb:3-2 product:... model:Pixel_7 ...
```

Authorization: plug in over USB, accept the “Allow USB debugging?” dialog on
the phone, then re-run `adb devices` — it must say `device` (not `unauthorized`).

Wireless is optional after the first USB authorization:

```bash
adb tcpip 5555
adb connect <device-lan-ip>:5555
```

## 3. Backend address + AI service address

The device reaches the host over the **LAN**, not `10.0.2.2` (that alias only
exists inside the emulator).

- Print the host’s LAN IP without committing it to the repo:

```bash
ipconfig getifaddr en0        # macOS wired; where ami en0/wifi varies
```

- The app’s base URL is set via `--dart-define=API_BASE_URL`.
  **Do not commit a private LAN IP or any secret.** Use a placeholder in docs:
  `http://192.168.x.y:8080/api/v1` and fill it in at build time only.

## 4. Required permissions

`AndroidManifest.xml` already declares:

- `android.permission.CAMERA` (runtime-granted)
- `<uses-feature android:name="android.hardware.camera" android:required="false"/>`
- `android:usesCleartextTraffic="true"` so a dev-HTTP LAN base URL works.
  Production uses HTTPS.

On install, pre-grant so the headless integration runner never blocks on a
dialog:

```bash
adb install -g -r build/app/outputs/flutter-apk/app-debug.apk
adb shell pm grant com.ecoloop.recycle_vision android.permission.CAMERA
adb shell dumpsys package com.ecoloop.recycle_vision | grep -A3 CAMERA
# → granted=true
```

## 5. Build the APK

```bash
cd mobile
flutter build apk --debug \
  --target=integration_test/android_camera_e2e_test.dart \
  --dart-define=API_BASE_URL=http://192.168.x.y:8080/api/v1 \
  --dart-define=DEMO_MODE=false
```

`apiBaseUrl` is a getter: Android debug defaults to `http://10.0.2.2:8080/api/v1`
only when no `API_BASE_URL` is given; the explicit LAN override wins on the
physical device (see `mobile/lib/core/app_config.dart` and
`docs/android-camera-e2e.md`).

## 6. Install the APK

```bash
adb install -g -r build/app/outputs/flutter-apk/app-debug.apk
```

## 7. Run the real stack

```bash
.venv/bin/python scripts/android_camera_e2e_stack.py
```

Starts (all real): mosquitto `:1884`, ai-service `:8051` (real model,
`OFFLINE_MODE=false`, dev-override envs poisoned to prove they are ignored),
backend `:8080` bound to `0.0.0.0` with `DEBUG_IMAGE_HASH=true`. Ctrl-C tears
down. Prereqs: local Postgres role `recycle/recycle`, db `recycle_vision_e2e`,
mosquitto at `/opt/homebrew/sbin/mosquitto`, free ports 1884/8051/8080.

The device talks to the backend at `http://192.168.x.y:8080/api/v1`; the app’s
WebSocket and the backend→ai-service hop are internal. Verify from the device
side by opening the debug URL in a browser on the phone or with:

```bash
curl -s http://192.168.x.y:8080/api/v1/health   # 404 → backend routing note:
# /api/v1 routes exist; /health is at the root path. Use the login route instead:
curl -s -X POST http://192.168.x.y:8080/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"demo@recycle.vision","password":"demo123"}'
```

## 8. Drive the physical-device E2E

The existing `mobile/integration_test/android_camera_e2e_test.dart` already
(a) captures a real frame, (b) proves byte identity against the backend debug
fingerprint route, (c) POSTs the real bytes to `/ai/predict`. On a physical
device it runs with the same drive command (do **not** use `adb reverse` here —
the device is on the LAN):

```bash
cd mobile
adb install -g -r build/app/outputs/flutter-apk/app-debug.apk
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/android_camera_e2e_test.dart \
  -d <physical-device-serial> \
  --use-application-binary=build/app/outputs/flutter-apk/app-debug.apk
```

For the full capture set described in sections 2–3, a camera-in-the-loop harness
(presenting each object and driving a fresh capture) is the intended driver.
The runtime hookpoints already exist: `CameraCaptureService.capture(...)`
returns `{jpegBytes, sha256Hex}`, and each frame is POSTed through the real
`ApiAiClassifier`. Wire per-object metadata (object_id, class, lighting,
background, orientation, distance) in the harness around those calls.

---

## Real object test set (minimums)

- **≥5 plastic objects**, **≥5 metal objects**, **≥5 paper objects**,
  **≥5 other objects**.
- Vary shape, size, color, brand, orientation, background across objects.
- Never reuse the same physical object for every capture.
- Capture **multiple frames per object** (at least 2; more are better).

### Camera conditions (each object, where possible)

- A. good indoor lighting (well-lit, shadows allowed but natural)
- B. weaker lighting (room light, still realistic — never pitch-black)
- C. different background (light vs dark, plain vs textured surface)
- D. different distance (close, ~25–40 cm; far, ~60–90 cm)
- E. slightly different orientation (tilt / rotate, keep the object identifiable)

Never deliberately create unrealistic images.

### Failure-case captures (no forcing of any result)

- empty background (no object)
- hand without waste
- very blurry frame
- very dark frame (but realistic)
- multiple unrelated objects together
- partially occluded object

Record the gate/classifier behavior verbatim for each; do not tune anything to
make them pass.

---

## Recording schema (per capture)

| field | source |
|---|---|
| object_id | harness-assigned unique id |
| class | human-labelled ground truth (plastic/metal/paper/other) — the AI prediction is NEVER ground truth |
| capture_id | per-capture unique id |
| lighting / background / orientation / distance | condition labels |
| prediction | `predicted_class` from `/ai/predict` |
| raw_confidence | `confidence` from `/ai/predict` (model softmax argmax) |
| calibrated_confidence | post-hoc mapping via `ai-service/models/calibration.json` (tool: `app/tools/calibrate.py`); recorded only if computed, else left empty |
| latency | `elapsed_ms` from the classifier response + end-to-end stopwatch |
| gate_state | `VALID_FRAME` / `LOW_QUALITY` / `NO_OBJECT` / `CORRUPT_IMAGE` |

Byte identity: for **at least one** physical capture, compare on-device
`sha256Hex` (from `CameraCaptureService`) against
`POST /debug/image-sha256` (auth-required, mounted only when
`DEBUG_IMAGE_HASH=true`) — they must be equal. The debug endpoint is
**never** exposed to users and **never** enabled in production.

Latency: record camera-capture, upload/network, gate, AI-inference, and total
API times; report **median and p95** where ≥5 samples exist.

---

## Results template (`docs/android-camera-e2e/physical-device-results.md`)

Per-object table, then overall:

| Object | Expected | Predicted | Confidence | Gate | Correct |
|--------|----------|-----------|------------|------|---------|

Then: total samples, correct, incorrect, accuracy, per-class precision, per-class
recall, macro F1, confusion matrix, gate false-rejection observations, OOD/
background observations, latency, byte-identity hash, decision on `model.onnx`.

Sample-size honesty: “initial physical-camera validation”, never
“production validation”, for 20–50 objects (or whatever the count actually is).

If the model does well → `model.onnx` unchanged. If it does not → **no retrain**;
report failing classes, failure patterns, lighting/background problems,
confidence behavior, gate problems, examples needing data, and recommend the
next data-collection step.

---

## 12. Software regression (after any physical run)

```bash
cd ai-service && ../.venv/bin/python -m pytest -q          # ≥82
cd ../backend && ../.venv/bin/python -m pytest -q         # ≥61
cd ../mobile && flutter analyze && flutter test -j 1      # analyze clean, ≥33
cd ../hardware-simulator && ../.venv/bin/python -m pytest -q  # ≥27
../../.venv/bin/python ../scripts/e2e_real_chain.py        # 30/30
```