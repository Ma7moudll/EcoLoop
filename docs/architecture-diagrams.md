# EcoLoop — Full Architecture Diagrams

Reference for every major flow in the system. Generated from the verified
implementation (see `docs/architecture.md` for prose, `docs/mqtt-contract.md`
for topic payloads).

---

## 1. High-Level Component Map

```
+--------------------------------------------------------------------------+
|                              STUDENT (phone)                              |
|   Flutter app — com.ecoloop.ecoloop                                |
|   5 tabs: Home | Impact | Rewards | Leaderboard | Profile    [ SCAN FAB ] |
+---------------------+---------------------------------------+------------+
                      | HTTPS  /api/v1/*                       | WSS
                      | (JWT bearer)                           | /ws/deposits/{op}
                      v                                        | ?token=JWT
+--------------------------------------------------------------+-----------+
|                        BACKEND  FastAPI  :8080                             |
|                                                                            |
|  auth.py        register(no token) / login(JWT) / forgot / reset / verify  |
|  user_data.py   profile / history / impact / leaderboard / challenges      |
|  deposit.py     session create / capture / cancel + X-Station-Key gates    |
|  stations.py    station list & status                                      |
|  ai.py          proxy -> AI service /predict                               |
|  rewards.py     catalog / redeem(idempotent) / cancel / my redemptions     |
|  admin.py+ui.py CRUD everything + inline console HTML/JS                   |
|  ws.py          per-operation live frames (token + ownership + revocation) |
|                                                                            |
|  services: deposit_service | reward_service | challenge_service            |
|            points_transaction (atomic award) | leaderboard_service         |
|            predict_service | seed                                          |
|  security: JWT(token_version revocation) | rate limiters | station keys    |
+----+------------------+------------------+-------------------+------------+
     |                  |                  |                   |
     | SQL              | HTTP /predict    | MQTT pub/sub      | SMTP(console
     v                  v                  v (TLS 8883 prod)    |  in dev)
+-----------+   +---------------+   +---------------+          v
| Postgres  |   | AI SERVICE    |   | MQTT BROKER   |   +-------------+
| recycle_  |   | FastAPI :8051 |   | HiveMQ Cloud  |   | Mailer      |
| vision    |   |               |   | (dev: mosq    |   | (console    |
|           |   | quality gate  |   |  :1884)       |   |  backend)   |
| users     |   | ONNX          |   +-------+-------+   +-------------+
| faculties |   | MobileNetV3-S |           |
| stations  |   | 4 classes:    |           | ecoloop/stations/{code}/
| deposits  |   | plastic metal |           |   command | capture_request
| waste_    |   | paper other   |           |   state | sensor | event |
|  events   |   +-------+-------+           |   heartbeat
| ai_predic-|           |                   |
|  tions    |           |                   v
| sessions  |   +-------------------------------+
| routing_  |   | STATION HARDWARE (ESP32 /     |
|  policies |   | hardware-simulator)           |
| challenges|   | ST-001: camera, chute,        |
| user_chal-|   | weight sensor, beam, bins 1-4 |
|  lenges   |   +-------------------------------+
| rewards   |
| reward_   |
|  redemp-  |
|  tions    |
| auth_     |
|  tokens   |
| leader-   |
|  board_*  |
+-----------+
```

---

## 2. Deposit Flow — Capture-First (the REAL chain)

```
 STUDENT            BACKEND                STATION CAM        AI :8051      SIMULATOR/ESP32
    |  Scan (FAB)      |                        |                |                |
    |--POST /deposit/--|                        |                |                |
    |  session         |                        |                |                |
    |                  |--MQTT capture_request->|                |                |
    |                  |   (station/{code}/...) |                |                |
    |                  |<--HTTP POST /capture---| frame bytes    |                |
    |                  |   (X-Station-Key)      |                |                |
    |                  |     status=analyzing   |                |                |
    |                  |------/predict-------->|                |                |
    |                  |                       [ upload cap 10MB ]               |
    |                  |                       [ decode -> quality gate ]         |
    |                  |                       [ ONNX inference ]                 |
    |                  |<-- class+confidence---+                |                |
    |                  |  low conf? -> REJECTED (0 pts, audited) |                |
    |                  |--MQTT command: route-->|-------------------------------->-|
    |                  |   position, mode(auto/manual)                            |
    |<-WS/POLL states--|  routing . moving . ready . detecting . measuring        |
    |                  |                        item dropped, sensors fire        |
    |                  |<--MQTT event: deposit_result-----------------------------|
    |                  |    actual_position / weight / stable / beam / mech       |
    |                  |                                                          |
    |                  | GATES: station match . not expired . not terminal .      |
    |                  |        position match . min weight . stability .         |
    |                  |        beam seen . mechanical . chute at position     |
    |                  |                                                          |
    |                  | BEGIN TX                                                 |
    |                  |   insert WasteEvent                                      |
    |                  |   user.points += policy.potential_points                 |
    |                  |   upsert student+faculty leaderboard                     |
    |                  |   challenge bonus (savepoint: race-safe)                 |
    |                  | COMMIT                                                   |
    |<-WS terminal ----|  confirmed, +N points                                    |
```

**Invariant:** points exist ONLY after the physical `deposit_result` event.
No points at registration, scan, prediction, or session creation.

---

## 3. Authentication Lifecycle

```
 REGISTER                          LOGIN                          SESSION USE
 --------                          -----                          -----------
 POST /auth/register               POST /auth/login               Authorization: Bearer
  -> 201 {user} NO TOKEN            -> 200 {token, user}           decode + check:
  -> account created                rate-limited                    - signature (secret)
  -> points = 0                     password verify                 - exp
  -> NOT authenticated              hash compare                    - token_version match
        |                                 |                         - is_active
        v                                 v
 mobile: wipe old session,        stores token in                 logout ->
 push LoginScreen                 secure storage                  token_version++ kills
 "login to continue"              restore on boot ->              every session+WS of
                                  "Welcome back" screen,          that user everywhere
                                  NEVER silent Home               (global revocation)

 FORGOT/RESET: rate-limited; reset token single-use via atomic
 UPDATE..WHERE used_at IS NULL (concurrent clicks: exactly one winner); expires.
```

---

## 4. Redemption State Machine (rewards marketplace)

```
                         redeem (idempotency key,
                         conditional stock--, conditional points--)
                                   |
                     +-------------+-------------+
                     |                           |
                category=cash               category=code
                     |                           |
                status=pending             status=available
                (reservation held)         ECO-XXXXXX code issued
                     |                           |
        +------------+------------+        +-----+------+------------+
        |            |            |        |            |            |
    approve      fulfill       reject    mark-used    cancel      (merchant
   pending->   pending/      pending/    available   available     consumes)
    approved    approved      approved      ->used      ->cancelled
        |         ->fulfilled   ->rejected      |           |
        |            |            |           |        stock++ (if limited)
        |            |            |        stock stays  |
        |            |            |        (consumed)  points += spent
        |            |            |        NO refund   (exactly once, atomic)
        |            |         stock++
        |            |         points += spent
        v            v            v
   ALL transitions: guarded conditional UPDATE ... WHERE status=<pre-state>
   rowcount==0 -> loser refuses (409/422), NEVER double-refunds,
   NEVER double-restores stock. Idempotent replay returns original redemption.

   Insufficient balance/stock -> 409/422, NOTHING changes.
   Cash redemption without destination -> refused.
```

## 5. Deposit Session State Machine

```
 capture --> analyzing --> pending --> routing(1) --> moving(2) --> ready(3)
    ^           |                        --> detecting(4) --> measuring(5)
    |           |                                              |
    |           +-- low confidence --> REJECTED (-2)           |
    |           +-- AI down/gate --> back to CAPTURE (retake)   v
    |                                            CONFIRMED  (points!)
    |-- user cancel (non-terminal only) --> CANCELLED
    |-- TTL elapsed --------------------> EXPIRED
    |-- gate failure --------------------> REJECTED (audited WasteEvent, 0 pts)

 rank order enforced: late telemetry can never regress a session.
 TERMINAL = {confirmed, rejected, cancelled, expired} -- immutable.
 Duplicate deposit_result -> DuplicateDepositError, no double award.
```

## 6. Entity Relationships (core)

```
 Faculty 1---* User 1---* DepositSession *---1 Station
                  | 1---* AuthToken            |
                  | 1---* RewardRedemption *---1 Reward
                  | 1---* UserChallenge *---1 Challenge
                  | 1---* WasteEvent (audit row per deposit outcome)
 DepositSession 1---1 WasteEvent  (waste-{op} / waste-rej-{op})
 AiPrediction 1---* DepositSession (legacy phone path; station path = null)
 LeaderboardEntry: scope students(entity=user) | faculties(entity=faculty)
 FK rules: redemption.user CASCADE, redemption.reward RESTRICT,
           user_challenge UNIQUE(user_id, challenge_id),
           redemption UNIQUE(user_id, idempotency_key)
```

## 7. Deployment Topology

```
 DEV (this repo)                          PRODUCTION TARGET
 ----------------                        -------------------
 uvicorn backend  :8080                  TLS termination (nginx/caddy/managed)
 mosquitto local  :1884 (per-run pass)   backend behind proxy (+body-size limit)
 AI service       :8051                  HiveMQ Cloud TLS 8883 (ACL same shape)
 Postgres local   :5432                  managed Postgres + backup schedule
 emulator AVD + simulator                Play-signed APK, API_BASE_URL https://...
 flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1
                                         release APK REQUIRES --dart-define=https://...

 REQUEST PATH (defense in depth):
 Client -> TLS/reverse proxy -> proxy body limit -> FastAPI/AI
        -> app upload cap (10MB) -> decode -> quality gate -> ONNX
```

## 8. Security Layers (summary)

```
 L1 TLS everywhere (prod)              L5 JWT + token_version revocation
 L2 explicit CORS origins only         L6 role gates (admin 403/401 matrix)
 L3 X-Station-Key on camera routes     L7 atomic DB guards (balance/stock/status)
 L4 MQTT authenticated + per-station   L8 rate limits: login/register/forgot/
    ACL, no anonymous publish             reset/verify + 10MB AI upload cap
```
