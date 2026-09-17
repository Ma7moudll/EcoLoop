# Demo / Mock / Offline Audit

> **Resolution (2026-08-19):** every Class **A** runtime item below has been
> executed. The offline runtime (`mobile/lib/offline/`, `AppConfig.offlineMode`)
> is deleted, `DEMO_MODE` no longer exists, the demo login/badge/settings tile
> are gone, and `seed_demo_user` is opt-in. Under the FINAL station-camera
> architecture the phone-camera scan UX was also removed (`screens/scan/`,
> `camera_capture.dart`, `camera`/`image_picker`/`crypto` deps) and
> `docs/android-camera-e2e*.md` deleted; the phone now only identifies the
> station and the STATION camera is the sole classification source. The on-device
> E2E became `integration_test/station_capture_e2e_test.dart` (phone acts as an
> observer; the host stack + hardware simulator complete the drop) with
> `scripts/station_capture_e2e_stack.py`. This page remains as the historical
> audit record.

**Date:** 2026-08-18
**Scope:** every runtime path that can produce demo data, fake predictions, or
offline fallback, across `mobile/`, `backend/`, `ai-service/`,
`hardware-simulator/`, `infra/`, `scripts/`, `shared/`, `server/`, `docs/`.
**Goal:** remove ALL runtime demo behavior so the dev stack is fully real
(real AI via ONNX, real FastAPI backend, PostgreSQL, real Mosquitto, hardware
simulator speaking the real MQTT contract, real Flutter app) while keeping
every test suite green using its existing fixtures/mocks **internally**.

## Classification legend

| Class | Meaning |
|---|---|
| **A** | MUST REMOVE from runtime (demo data / fake prediction / offline fallback / demo account shortcut) |
| **B** | TEST fixture / mock — keep as-is (never reached by a real run) |
| **C** | SIMULATOR — allowed; emits real MQTT events, never writes DB rows directly |
| **D** | DOCS / dormant legacy — update text or document, do not delete blindly |

## Baseline (verified before this audit)

- AI service: 82 tests green; real ONNX classifier `models/model.onnx` +
  `calibration.json` present; gate (`NO_OBJECT`/`LOW_QUALITY`/`CORRUPT_IMAGE`)
  runs before the classifier → 422.
- Backend: 61 tests green; `points_transaction.award_points()` atomic;
  `LeaderboardService.repair()` rebuilds from real DB; `/ai/predict` appends
  `session` and calls the real AI via `AiServiceClient`; `seed()` is idempotent
  config-only seed (faculties, station, routing policy, counter + **demo user**).
- Hardware simulator: 27 tests green; MQTT-only contract.
- Mobile: 33 tests green + `flutter analyze` clean.
- Software E2E (`scripts/e2e_real_chain.py`): 30/30 green against a real stack
  (mosquitto 1884, ai-service 8051 real, backend 8080, Postgres).
- Only emulator-5554 attached (Android 16, API 36). No physical device.

---

## Findings

### 1. Mobile runtime — MUST REMOVE (A)

| File | What | Verdict |
|---|---|---|
| `mobile/lib/main.dart` | subscribes to `AppConfig.offlineMode`; injects `offlineOverrides()` when true | **A** — remove the offline branch entirely; always run real providers |
| `mobile/lib/offline/offline_backend.dart` | full in-memory fake backend: `Demo Student` S-DEMO, hardcoded leaderboard (`Hana Juma`/`Omar Saeed`/…), hardcoded history, `OfflineDepositRepository` (line 264), `OfflineAiClassifier`, pre-signed-in `OfflineAuthRepository` | **A** — delete the file + its directory once `main.dart` stops referencing it |
| `mobile/lib/core/app_config.dart:42` | `demoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: true)` | **A** — flip default to `false` |
| `mobile/lib/core/app_config.dart:45-46` | `offlineMode` compile-time flag | **A** — remove |
| `mobile/lib/core/app_config.dart:58` | `simulatedWeightGrams` | **A** — only used by the offline fake; remove |
| `mobile/lib/core/app_config.dart:52-54` | `minDepositWeightGrams` + comment | **A** — used only for demo UX copy; remove |
| `mobile/lib/screens/login_screen.dart:61-69` | `_demoLogin()` + "Try the demo account" button (fills `demo@ecoloop.app`/`demo123`) | **A** — remove button + handler |
| `mobile/lib/screens/home_screen.dart:45-48` | `if (AppConfig.demoMode) DemoBadge()` | **A** — remove (badge only renders under demo mode) |
| `mobile/lib/widgets/app_logo.dart:45` | `DemoBadge` widget | **A** — remove once home screen no longer uses it |
| `mobile/lib/screens/settings_screen.dart:30-36` | read-only "Demo mode" `SwitchTile` bound to `AppConfig.demoMode` | **A** — remove the tile; keep honest status read-outs |
| `mobile/lib/screens/scan/deposit_screen.dart:85-90` | offline branch (`if (AppConfig.offlineMode)` → `depositRepositoryProvider.awaitDeposit`) | **A** — remove branch; always use WebSocket channel |
| `mobile/lib/screens/scan/deposit_screen.dart:184,421` | `DemoBadgeInline` (only renders under `AppConfig.demoMode`) | **A** — remove |

No mobile test asserts `DemoBadge`/`DEMO` text (checked `home_screen_test`,
`login_screen_test`, `deposit_flow_test`, `deposit_status*`, `widgets_test`).

### 2. Mobile tests — keep (B)

| File | Note |
|---|---|
| `mobile/test/helpers.dart` | `FakeAuthRepository`/`FakeDataRepository`/`FakeDepositStatusChannel`/`fakePrediction(source: 'demo')` are **internal test doubles** — keep |
| `mobile/test/offline_mode_test.dart` | exercises `offlineOverrides()` — the ONLY test tied to the removed offline runtime. Classified **B** but will be removed together with the offline runtime, and replaced with a test that the app surfaces a connection error honestly |
| `mobile/integration_test/android_camera_e2e_test.dart` | real on-device camera E2E; `E2E_USER`/`E2E_PASSWORD` default to demo creds (harness accounts, injected at run time); asserts `prediction.source == 'ai'` — **B**, keep |

### 3. Backend — partial (A for demo user, B for fixtures)

| File | What | Verdict |
|---|---|---|
| `backend/app/services/seed.py` | idempotent seed. Keeps faculties, `st-001`, routing policy, `OperationCounter`. Demo user (`Demo Student` / `demo@ecoloop.app` / `demo123` / `points=45`) is now gated behind `seed_demo_user=True` | **A (resolved)** — default seed creates config only; demo user only via explicit `SEED_DEMO_USER=true` |
| `backend/app/main.py:40-42` | lifespan runs `seed()` + `LeaderboardService.repair()` when `SEED_ON_STARTUP` | keep — `repair()` rebuilds leaderboard from real `users`/`points` |
| `backend/app/config.py` | `seed_on_startup: bool = True` (dev config seed); new `seed_demo_user: bool = False` gates the demo account | keep (dev convenience), re-audit prod |
| `backend/tests/conftest.py` | `FakeAi`, `FakePublisher`, `SEED_ON_STARTUP=true`, clean schema per test, `DEMO_EMAIL`/`DEMO_PASSWORD` | **B** — keep; these are test fixtures |
| `backend/app/routers/auth.py` | real register/login; register assigns `points=0`, requires existing faculty | keep (already real) |
| `backend/app/services/points_transaction.py`, `leaderboard_service.py`, `challenge_service.py`, `impact_service.py`, `predict_service.py`, `user_data.py`, `mqtt/*` | compute/award from real DB rows + real AI + real MQTT | keep (already real) |

**Important interplay:** `backend/tests/conftest.py` seeds the demo user and
logs in as `demo@ecoloop.app` in every test, and `scripts/e2e_real_chain.py`
expects `demo@ecoloop.app` with `points=45`. If `seed()` stops creating the
demo user, the backend suite and the software E2E break. Resolution:
- The **default runtime** seed must NOT create demo users → move demo-user
  creation behind an explicit opt-in env flag (e.g. `SEED_DEMO_USER=true`).
- Test/CI environments set that flag (conftest + `e2e_real_chain.py`) so suites
  stay green with their existing fixture accounts.

### 4. AI service — keep (B/C for fixtures, already real)

| File | What | Verdict |
|---|---|---|
| `ai-service/app/config.py` | `classifier` default `real`; `development` isolated test fixture | keep |
| `ai-service/app/main.py` | gate before classifier; real ONNX | keep |
| `ai-service/tests/fixtures/` (`high_conf_plastic.png`, `medium_conf.png`, `low_conf.png`) | real captured/provenance images used by tests + software E2E | **B/C** — keep |
| `ai-service/data/station_capture/` | 4800 real station photos (1200/class) — the source for `generate_real_dev_activity.py` | keep |

### 5. Hardware simulator — keep (C)

`hardware-simulator/` publishes real MQTT events and never writes DB rows.
`hardware/load_cell.py` seedable RNG is deterministic (fine). The only
DB-touching script is `scripts/e2e_real_chain.py`'s `_truncate_db()` (test
harness, **B**).

### 6. Infrastructure / env — A

| File | What | Verdict |
|---|---|---|
| `infra/docker-compose.yml` | `ai-service` runs `AI_SERVICE_CLASSIFIER: development` + empty `AI_MODEL_PATH` | **A** — flip to `real` + `models/model.onnx` |
| `infra/docker-compose.yml` | backend uses compose MQTT 1883 vs host scripts 1884 | document; keep dev defaults consistent |
| `.env.example` | `AI_SERVICE_CLASSIFIER=real` already; no `SEED_DEMO_USER`; mobile `DEMO_MODE`/`OFFLINE_MODE` not represented | **D** — extend with dev/test/prod sections |
| `scripts/android_camera_e2e_stack.py`, `scripts/e2e_real_chain.py` | start real stack; use demo account as harness user; fixtures | **B** — keep; will set `SEED_DEMO_USER=true` |
| `scripts/test_real_camera.py` | local inference probe over real model | **C/D** — keep |

### 7. `server/` legacy Dart package — D (dormant)

`server/` (shelf, JSON-file store) ships its own `seed.dart`
(`demo@ecoloop.app`/`demo123`, demo leaderboard, fake AI in `ai.dart`,
`DEMO_MODE` default `true`). It is **NOT** referenced by any script, doc, or
`mobile/pubspec.yaml` (mobile depends only on `path: ../shared`). Classified
**D**: dormant legacy, leave + document; never wire into the real stack.

### 8. Docs — D

`docs/architecture.md:46,158` (offline fallback preserved / demo badge),
`docs/api-contract.md:20` (demo user example), `docs/android-camera-e2e.md` and
`docs/android-physical-camera-e2e.md` (`DEMO_MODE=false` flags) — update wording
to reflect the new reality (no offline runtime, demo user opt-in).

---

## Implementation plan (post-audit)

1. **Mobile** (A items above): remove offline runtime + demo badge + demo login
   shortcut + demo settings tile; flip `DEMO_MODE` default to `false`; always
   use the real WebSocket deposit channel. Replace `offline_mode_test.dart`
   with an honest "backend unreachable → ErrorScreen, no silent fallback" test.
2. **Backend**: gate demo-user seeding behind `SEED_DEMO_USER` (default false);
   conftest + `e2e_real_chain.py` set it true so suites stay green.
3. **Infra**: `docker-compose.yml` ai-service → `real`; extend `.env.example`.
4. **Scripts**: `scripts/reset_dev_db.py`, `scripts/dev_up.sh`,
   `scripts/dev_health.sh`, `scripts/generate_real_dev_activity.py` (10 deposits
   through the real API → MQTT → simulator chain, using real station-capture
   images; gate rejections recorded, never overridden).
5. **Regression**: AI 82 / backend 61 / sim 27 / flutter 33+analyze / E2E 30/30.
6. **Final live demo** on emulator-5554 against the real stack; DB before/after
   counts; final report with numbered items, no fabricated results.
