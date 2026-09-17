# EcoLoop Hardening Audit — Final Report

**Date:** 2026-08-21 · **Scope:** full business-logic / auth / authz /
mobile-UX / DB-integrity / admin-access audit of `ecoloop`, with every
F-class finding fixed in place (no architecture rebuild, no demo/mock
reintroduction, no security weakening).

---

## 1. Findings and resolutions

### F1 — Real credential committed to the repo (CRITICAL)
`infra/.env.example` contained the real HiveMQ broker password (`CUC_2026`).
**Fixed:** file replaced with placeholder-only template; no secret material
remains. Rotation of the cloud credential is an operator action outside the
repo.

### F2 — Email verification gate locked out all new users (CRITICAL)
The uncommitted auth hardening made login require `email_verified=true`, but
the only mail provider available in dev was the console printer — every new
account was permanently locked out.
**Fixed:** explicit config knob `email_verification_required` (default
`False`); the gate is enforced only when it is set; production guard refuses
`EMAIL_VERIFICATION_REQUIRED=true` with `EMAIL_PROVIDER≠smtp`
(backend/app/config.py).

### F3 — Faculty model was demo fiction (HIGH)
Server defaulted missing faculty to `"engineering"`; mobile registration sent
no faculty at all; seed data carried forbidden faculties (science / commerce /
medicine).
**Fixed:** canonical faculties `ENGINEERING`, `PHYSICAL_THERAPY`,
`ART_DESIGN`; legacy ids remapped by migration `0005_faculty_canonical`;
registration requires a valid facultyId (server-side validation); register
screen has a faculty picker; legacy remap keeps old rows coherent.

### F4 — Mobile Settings exposed infrastructure details (MEDIUM)
The Settings screen displayed the raw API base URL.
**Fixed:** screen rebuilt — Account (edit profile, change password), Support
(help/FAQ, contact, privacy), About, Logout. No endpoints or URLs shown.

### F5 — No way to bootstrap an administrator (HIGH)
Admin role existed in the schema but nothing could create the first admin.
**Fixed:** `scripts/create_admin.py` — interactive hidden password prompt
(min 12 chars, confirmed twice), `--force` to rotate, bumps `token_version`,
never accepts a password argument. Verified live against Postgres.

### F6 — No admin visibility (HIGH)
Admins could mutate stations/users/challenges but see nothing aggregated.
**Fixed:** read-only dashboard endpoints — `/admin/overview`, `/admin/faculties`
(ranked), `/admin/stations` (DB status + live MQTT state), `/admin/deposits`
(authoritative points via WasteEvent outer join), plus a searchable/paged
student directory (`GET /admin/users?q=&faculty=&limit=&offset=`) exposing
student codes and faculty display names. All inherit the router-level
`require_admin`. A server-rendered inert single-page console lives at
`GET /api/v1/admin/ui` (HTML shell contains no data; every fetch is
token-gated). Verified live: student token → **403** on all five endpoints;
no token → **401**.

### F7 — No credential self-service (MEDIUM→HIGH)
No change-password endpoint; no profile edit.
**Fixed:** `POST /auth/change-password` (requires current password, ≥8 chars,
rate-limited, bumps `token_version`) and `PATCH /users/me/profile`
(name/faculty only — email, student code, role are immutable). Mobile flows
added in Settings.

### Token-version invalidation (new control)
JWTs now carry a `ver` claim bound to `users.token_version` (migration
`0006`). `get_current_user` rejects version mismatch (401); WebSocket
ownership checks validate it too. Change-password and reset-password bump the
version, killing every outstanding token. **Verified live:** token obtained
before a password change returns 401 on `/auth/me` afterwards; fresh login
works.

### Points-on-new-account rumor — investigated and disproven
Empirically verified end-to-end on the live stack: registration returns
`points: 0`; DB default is 0; points move ONLY through the atomic
`award_points()` transaction keyed on waste id `waste-{operation_id}` with a
unique constraint. Nonzero balances observed earlier were dev artifacts
(restored u-demo token via bootstrap, activity-generator users), not a bug.
The seeded generator/demo users are disabled under the current
`SEED_DEMO_USER=false` startup configuration.

## 2. Bugs found by the regression suite (and fixed)

| Bug | Where | Fix |
|---|---|---|
| Commit before consuming `UPDATE…RETURNING` cursor → SQLite `cannot commit transaction - SQL statements in progress`; race winner decided after commit | `app/routers/auth.py::_consume_token` | fetch row → then commit; winner check before side effects |
| Forgot/reset/verify/change rate-limit buckets not reset between tests → cross-test 429 cascade (39 setup errors) | `tests/conftest.py` | reset `_forgot_limiter`, `_reset_limiter`, `_verify_limiter` per test |
| Challenge progress `KeyError` for classes with zero deposits | `app/services/challenge_service.py` | `progress.get(cls, 0.0)` everywhere |
| Admin UI route registered at `/ui` instead of `/admin/ui` | `app/routers/admin_ui.py` | corrected path |
| Shared-package spec getter deleted, breaking threshold test | `shared/lib/src/confidence_policy.dart` | restored `confidenceThresholdsValid` |
| Stale test expectations (old faculty ids), prod-config fixture missing newly-required fields | tests | updated |
| `create_admin.py` imported nonexistent `init_db` | scripts | uses `create_tables()` |

## 3. Verification evidence

- **Backend:** `pytest`: **141 passed** (was 2 failed + 39 errors before fixes).
- **Mobile:** `flutter analyze`: **0 issues**; `flutter test`: **29/29 pass**.
- **Migrations:** live DB stamped through already-applied 0003/0004, then
  upgraded `0005_faculty_canonical` + `0006_user_token_version`
  (`alembic current` → `0006_user_token_version (head)`).
- **Live stack** (mosquitto :1884 authenticated, AI :8051 real ONNX, backend
  :8080 + Postgres; `/health` → db/mqtt/ai all `ok`):
  - Register `live-test@uni.edu` → `points: 0`, `facultyName: "Engineering"`.
  - Profile patch → name/faculty updated everywhere.
  - Wrong current password → 401; correct change → all old tokens dead (401);
    re-login with new password OK.
  - Admin bootstrap via script; overview shows real aggregates (8 students,
    12 deposits, 0.22 kg); directory search `?q=live` finds the renamed user;
    deposits feed shows authoritative per-deposit points.
  - Authorization matrix re-proven live: student 403 ×5 endpoints, anonymous 401.

## 4. Remaining operator actions (outside repo)

1. Rotate the exposed HiveMQ credential from F1 (it must be considered
   compromised).
2. Set strong `JWT_SECRET`, `STATION_API_KEY`, SMTP credentials and
   `EMAIL_VERIFICATION_REQUIRED=true` when deploying; the production guard
   now enforces these categories at startup.
3. Support contact in the mobile app is a placeholder
   (`support@ecoloop.example.edu`) — replace with the university's real
   address before release.
