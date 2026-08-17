# Android camera → real AI → deposit: on-device E2E

Proves the **real Android camera path** end-to-end: the Flutter app captures a
frame with the device camera, the exact captured bytes travel from the phone to
the production backend, and the backend hands them to the real AI-service gate
and classifier.

This E2E deliberately does **not** use: hardcoded image paths, fixture images,
a fake/mocked camera, mocked HTTP, fake predictions, or offline/demo mode
(`DEMO_MODE=false`, real `ApiAiClassifier` all the way).

## What is proven vs not proven

| proof | status | how |
|---|---|---|
| device camera produces real JPEG bytes | proven | `CameraCaptureService` captures via `camera` plugin |
| those exact bytes reach the backend | proven | byte-identity SHA-256 (debug-only echo route) matches |
| backend talks to real AI service | proven | real `/ai/predict`, `OFFLINE_MODE=false`, dev-override poisoned |
| quality gate runs before classification | proven | emulator's virtual scene honestly rejected as LOW_QUALITY (HTTP 422) |
| corrupt bytes rejected without decoder crash | proven | 422 CORRUPT_IMAGE |
| real plastic/paper/metal → deposit on emulator | **not proven here** | the emulator's virtual scene is not a real object (see Limitations) |

## Architecture touched

```
Flutter (mobile/)
  services/camera_capture.dart        CameraController + takePicture + SHA-256
  integration_test/android_camera_e2e_test.dart   on-device E2E driver
  core/app_config.dart                apiBaseUrl getter (debug→10.0.2.2 mapping)
  android/.../AndroidManifest.xml     CAMERA permission, cleartext for dev
  test/camera_capture_test.dart       unit tests (SHA-256 vectors, config mapping)

Backend (backend/)
  app/routers/debug.py                POST /api/v1/debug/image-sha256  (only when DEBUG_IMAGE_HASH=true)
  app/config.py                       debug_image_hash flag
  app/routers/__init__.py             debug_router export
  app/main.py                         mount guard
  tests/test_debug_image_hash.py      not mounted by default; echoes exact SHA-256

Stack (scripts/)
  scripts/android_camera_e2e_stack.py  mosquitto + ai-service + backend for the run
```

## 1. Android setup

- device/emulator with ARM64 Flutter debug build (the virtual scene camera
  shown here ran on AVD `sdk_gphone64_arm64`, API 36).
- `AndroidManifest.xml`:
  - `<uses-permission android:name="android.permission.CAMERA"/>`
  - `<uses-feature android:name="android.hardware.camera" android:required="false"/>`
  - `android:usesCleartextTraffic="true"` on `<application>` so a **development**
    HTTP base URL (emulator loopback / LAN) is allowed. Production uses HTTPS.

## 2. Camera permission (the one footgun)

The integration runner reinstalls the APK on every `flutter test`/`drive` run,
which resets Android runtime permissions. The camera plugin requests CAMERA at
runtime — and that request dialog **hangs** the headless test. Two working
options (both used here):

```bash
# option A: keep the app installed, then grant (drive does not reinstall)
adb install -g -r app-debug.apk
adb shell pm grant com.ecoloop.recycle_vision android.permission.CAMERA

# option B (used for the recorded runs): install the built test APK with the
# -g flag so no dialog is ever shown
adb install -g -r build/app/outputs/flutter-apk/app-debug.apk
```

Verify: `adb shell dumpsys package ... | grep -A3 CAMERA` → `granted=true`.

## 3. API base URL

`AppConfig.apiBaseUrl` is now a **getter**:

- Android **debug** builds default to `http://10.0.2.2:8080/api/v1` (host
  loopback as seen from the emulator) when no override is provided. This is the
  only place the emulator mapping lives; release builds stay on the real URL.
- Any explicit `--dart-define=API_BASE_URL=...` wins. Physical device on LAN:

  ```bash
  flutter drive ... --dart-define=API_BASE_URL=http://192.168.x.y:8080/api/v1
  ```

- The E2E used an adb reverse for determinism:
  `adb reverse tcp:8080 tcp:8080` + `API_BASE_URL=http://127.0.0.1:8080/api/v1`
  (tunnels over adb, bypassing the emulator's virtual NIC, which in this image
  had `Active default network: none`).

## 4. Run the stack

```bash
.venv/bin/python scripts/android_camera_e2e_stack.py
# starts (real):
#   mosquitto    :1884
#   ai-service   :8051   real model, OFFLINE_MODE=false
#   backend      :8080   HOST=0.0.0.0 DEBUG_IMAGE_HASH=true
# Ctrl-C cleans up.
```

`DEBUG_IMAGE_HASH=true` mounts the debug-only echo route
`POST /api/v1/debug/image-sha256`. It is **auth-required** and is never mounted
in normal builds; it exists solely so the E2E can prove the backend saw the
exact bytes — it can never award points or influence classification.

## 5. Run the E2E

```bash
cd mobile
REPO=.. # path to repo root

# 1) build the test APK (dart-defines baked in)
flutter build apk --debug \
  --target=integration_test/android_camera_e2e_test.dart \
  --dart-define=API_BASE_URL=http://127.0.0.1:8080/api/v1 \
  --dart-define=DEMO_MODE=false

# 2) install with permissions pre-granted (no dialog)
adb install -g -r build/app/outputs/flutter-apk/app-debug.apk

# 3) drive the already-installed app (drive does not reinstall → grant persists)
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/android_camera_e2e_test.dart \
  -d emulator-5554 \
  --use-application-binary=build/app/outputs/flutter-apk/app-debug.apk
```

### What the two tests assert

1. **`real camera JPEG reaches the real backend byte-for-byte`**
   - initializes the real camera, captures a JPEG (retries up to 4× because the
     emulator virtual-camera HAL can wedge between runs),
   - computes SHA-256 of the captured bytes,
   - asserts the backend echo returns the **same** SHA-256,
   - POSTs the bytes to the real `/ai/predict`; if the gate accepts, asserts
     `prediction.source == 'ai'` (never demo/mock).
2. **`corrupt bytes are rejected as HTTP 422 by the real gate`**
   - non-image bytes → real backend + gate return 422 CORRUPT_IMAGE (no decoder
     crash, no fake classification).

### Recorded result (emulator virtual-scene camera)

```
CAMERA_STEP attempt 1 frame captured
CAPTURED sha256=f379b06b742fcc267ce039209429bbf03d2e2d51acc8e87726bfb967174bdc73 size=10183
GATE_REJECTION status=422 error=Image quality is too low. Move closer or improve the lighting.
CORRUPT_REJECTION status=422 error=Unreadable image: could not decode payload
00:11 +3: All tests passed!
```

`docs/android-camera-e2e/emulator-capture-evidence.jpg` is the actual frame the
emulator camera produced (Sony/google virtual-scene JPEG, 640×480, EXIF
`model=sdk_gphone64_arm64Google`). Its SHA-256 matches the CAPTURED value above,
which is the same hash the backend echoed — i.e. the backend saw byte-for-byte
what the camera produced. The gate honestly rejected that frame as LOW_QUALITY;
no prediction was fabricated.

## 6. Deposit flow (software E2E — separate from the camera E2E)

The camera E2E proves capture→AI. **Deposits** are a separate pipeline;
`scripts/e2e_real_chain.py` drives the full software chain (login → scan →
predict → machine command → deposit → points) through the real simulator,
mosquitto, backend, and AI service. Points are only ever awarded after a
validated physical deposit event arrives over MQTT — never at scan time, and
never from this debug route. **The camera E2E never awards points.**

## 7. Regression

Run after any change:

```bash
cd ai-service && ../.venv/bin/python -m pytest -q            # ≥82
cd ../backend && ../.venv/bin/python -m pytest -q           # ≥59
cd ../mobile && flutter analyze && flutter test -j 1        # analyze clean, ≥27
cd integration_test && dart run ../../simulator/...          # simulator harness ≥27
../../.venv/bin/python ../scripts/e2e_real_chain.py         # 30/30 (software E2E)
```

## 8. Honest limitations

- The on-device E2E ran on an emulator whose camera shows a **virtual scene**,
  not a real plastic bottle / paper sheet / metal can. The byte path is
  proven, but scenario grades (plastic/paper/metal acceptance) are NOT
  established on this emulator camera — the gate correctly rejected the
  virtual scene. Physical devices (`hw.camera.back=emulated` is only for AVD
  testing on `pentest_avd`) are required for genuine object scenarios.
- Repeated camera runs can wedge the emulator's camera HAL; the test retries,
  and a device reboot restores it. This is an emulator artifact, not an app bug.
- The debug SHA-256 route can echo any bytes (proving byte identity) but is
  build-gated, auth-required, and can never influence classification or points.