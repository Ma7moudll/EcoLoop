"""End-to-end proof of the REAL deposit chain on real services.

Starts real processes (not TestClient): mosquitto broker, the ai-service
(FastAPI), and the backend (FastAPI + SQLAlchemy against PostgreSQL), then
drives every deposit scenario through the real HTTP + MQTT path with an
in-process EcoLoopSimulator acting as the ESP32 and a real WebSocket client
observing live status.

This is the standing proof that points are only ever awarded by validated
physical sensor events over MQTT — the HTTP layer and WebSocket can never
award points.

    scripts/e2e_real_chain.py

Prerequisites: local PostgreSQL (role recycle/recycle), mosquitto at
/opt/homebrew/sbin/mosquitto, the project venv, and free ports 1884/8051/8080.
"""
from __future__ import annotations

import os
import socket
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PYTHON = str(ROOT / ".venv" / "bin" / "python")
MOSQUITTO_BIN = Path("/opt/homebrew/sbin/mosquitto")
AI_MODEL_PATH = ROOT / "ai-service" / "models" / "model.onnx"
FIXTURES_DIR = ROOT / "ai-service" / "tests" / "fixtures"

HOST = "127.0.0.1"
MQTT_PORT = 1884
AI_PORT = 8051
API_PORT = 8080

DB_URL = (
    "postgresql+psycopg2://recycle:recycle@localhost:5432/recycle_vision_e2e"
)
JWT_SECRET = "e2e-secret-not-for-prod"

DEMO_EMAIL = "demo@recycle.vision"
DEMO_PASSWORD = "demo123"

os.environ.setdefault("SIMULATOR_RAMP_STEP", "0")
sys.path.insert(0, str(ROOT / "hardware-simulator"))

import httpx  # noqa: E402
import psycopg2  # noqa: E402

from hardware import Carriage, LoadCell  # noqa: E402
from scenarios import DepositPlan  # noqa: E402
from simulator import EcoLoopSimulator  # noqa: E402


def _port_free(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.3)
        return s.connect_ex((HOST, port)) != 0


def _wait_port(port: int, timeout: float = 30.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not _port_free(port):
            return
        time.sleep(0.2)
    raise RuntimeError(f"port {port} never came up")


def _fixture_bytes(name: str) -> bytes:
    """Confidence-band fixture images curated by the training pipeline from
    the real model (see ai-service/app/training/train.py / fixtures.json)."""
    path = FIXTURES_DIR / name
    if not path.exists():
        raise SystemExit(
            f"fixture {path} missing — run the training pipeline to curate it"
        )
    return path.read_bytes()


def _connect_pg():
    conn = psycopg2.connect(
        host="localhost", port=5432, user="recycle", password="recycle",
        dbname="recycle_vision_e2e",
    )
    conn.autocommit = True
    return conn


def _truncate_db() -> None:
    conn = _connect_pg()
    with conn.cursor() as cur:
        cur.execute(
            "TRUNCATE waste_events, deposit_sessions, ai_predictions "
            "RESTART IDENTITY CASCADE"
        )
        cur.execute(
            "UPDATE users SET points = 45 WHERE email = %s",
            (DEMO_EMAIL,),
        )
    conn.close()


def _force_expire(session_id: str) -> None:
    conn = _connect_pg()
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE deposit_sessions SET expires_at = %s WHERE operation_id = %s",
            (
                datetime.now(timezone.utc).replace(tzinfo=None)
                - timedelta(seconds=5),
                session_id,
            ),
        )
    conn.close()


class ScenarioControl:
    """Single-threaded control hand-off between the driver (HTTP thread) and
    the simulator's MQTT command handler."""

    def __init__(self) -> None:
        self.plan: DepositPlan | None = None
        self.hold_seconds = 0.0
        self.received: list[dict] = []

    def take_plan(self) -> DepositPlan | None:
        plan = self.plan  # None -> the physical drop never happens
        self.plan = None
        return plan


def main() -> None:
    # -- prerequisites ---------------------------------------------------------
    assert MOSQUITTO_BIN.exists(), f"mosquitto not found at {MOSQUITTO_BIN}"
    assert AI_MODEL_PATH.exists(), (
        f"trained model not found at {AI_MODEL_PATH} — run the training pipeline first"
    )
    if not _port_free(MQTT_PORT):
        raise SystemExit(f"port {MQTT_PORT} busy — stop the running broker")
    if not _port_free(AI_PORT):
        raise SystemExit(f"port {AI_PORT} busy")
    if not _port_free(API_PORT):
        raise SystemExit(f"port {API_PORT} busy")

    procs: list[subprocess.Popen] = []

    try:
        # -- mosquitto ----------------------------------------------------------
        conf = tempfile.NamedTemporaryFile(mode="w", suffix=".conf", delete=False)
        conf.write(
            f"listener {MQTT_PORT}\n"
            "allow_anonymous true\n"
            "max_queued_messages 1000\n"
            "message_size_limit 0\n"
        )
        conf.close()
        procs.append(subprocess.Popen(
            [str(MOSQUITTO_BIN), "-c", conf.name, "-v"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        ))
        _wait_port(MQTT_PORT)

        # -- ai-service ---------------------------------------------------------
        def start_ai() -> subprocess.Popen:
            env = dict(os.environ)
            env.update({
                "PYTHONPATH": str(ROOT / "ai-service"),
                "AI_SERVICE_CLASSIFIER": "real",
                "AI_MODEL_PATH": str(AI_MODEL_PATH),
                # Production inference MUST NOT read development overrides;
                # they are set to poison values to prove the real path ignores them.
                "DEVELOPMENT_FORCE_CLASS": "plastic",
                "DEVELOPMENT_FORCE_CONFIDENCE": "0.99",
            })
            return subprocess.Popen(
                [PYTHON, "-m", "uvicorn", "app.main:app", "--port", str(AI_PORT),
                 "--log-level", "warning"],
                cwd=str(ROOT / "ai-service"), env=env,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )

        ai_proc = start_ai()
        procs.append(ai_proc)
        _wait_port(AI_PORT)

        # -- backend -------------------------------------------------------------
        backend_env = dict(os.environ)
        backend_env.update({
            "PYTHONPATH": str(ROOT / "backend"),
            "DATABASE_URL": DB_URL,
            "MQTT_BROKER_HOST": HOST,
            "MQTT_BROKER_PORT": str(MQTT_PORT),
            "AI_SERVICE_URL": f"http://{HOST}:{AI_PORT}",
            "JWT_SECRET": JWT_SECRET,
            "SEED_ON_STARTUP": "true",
            "DEBUG": "false",
        })
        backend_log = open("/tmp/e2e_backend.log", "w")
        procs.append(subprocess.Popen(
            [PYTHON, "-m", "uvicorn", "app.main:app", "--port", str(API_PORT),
             "--log-level", "info"],
            cwd=str(ROOT / "backend"), env=backend_env,
            stdout=backend_log, stderr=subprocess.STDOUT,
        ))
        _wait_port(API_PORT)

        # Backend lifespan created the schema and seeded; reset transaction
        # state so repeated runs stay idempotent (demo user starts at 45 pts).
        _truncate_db()

        # -- simulator ------------------------------------------------------------
        from config import SimConfig
        cfg = SimConfig()
        cfg.broker_host = HOST
        cfg.broker_port = MQTT_PORT
        cfg.movement_time_seconds = 0.0
        sim = EcoLoopSimulator(
            config=cfg,
            carriage=Carriage(initial_position=1, movement_time_per_step=0.0),
            load_cell=LoadCell(noise_grams=0, seed=7),
        )
        control = ScenarioControl()

        def on_command(command: dict) -> None:
            control.received.append(command)
            plan = control.take_plan()
            if plan is None:
                return
            if control.hold_seconds:
                time.sleep(control.hold_seconds)
            try:
                sim.run_plan(
                    command["operation_id"],
                    command.get("destination_position"),
                    plan,
                )
            except Exception:
                pass

        sim.mqtt.set_command_handler(on_command)
        sim.mqtt.start(cfg.command_topic())
        assert sim.mqtt.connected.wait(10), "simulator not connected"
        time.sleep(0.5)

        # -- HTTP client -----------------------------------------------------------
        client = httpx.Client(base_url=f"http://{HOST}:{API_PORT}", timeout=20.0)
        login = client.post("/api/v1/auth/login", json={
            "email": DEMO_EMAIL, "password": DEMO_PASSWORD,
        })
        assert login.status_code == 200, login.text
        token = login.json()["token"]
        headers = {"Authorization": f"Bearer {token}"}

        # -- helpers -----------------------------------------------------------------
        results: list[str] = []
        passes = 0
        failures = 0

        def record(name: str, ok: bool, detail: str = "") -> None:
            nonlocal passes, failures
            if ok:
                passes += 1
                line = f"[PASS] {name}"
                results.append(line)
                print(line)
            else:
                failures += 1
                line = f"[FAIL] {name}: {detail}"
                results.append(line)
                print(line)

        def points_now() -> int:
            return client.get("/api/v1/users/me", headers=headers).json()["user"]["points"]

        def predict_bytes(blob: bytes) -> dict:
            r = client.post(
                "/api/v1/ai/predict", headers=headers,
                files={"image": ("capture.png", blob, "image/png")},
            )
            assert r.status_code == 200, r.text
            return r.json()

        def predict_fixture(name: str) -> dict:
            return predict_bytes(_fixture_bytes(name))

        def create_session(prediction_id: str) -> dict:
            r = client.post(
                "/api/v1/deposit/session", headers=headers,
                json={"ai_prediction_id": prediction_id, "station_id": "st-001"},
            )
            assert r.status_code == 200, r.text
            return r.json()

        def wait_status(op_id: str, target: str, timeout: float = 20.0) -> dict:
            deadline = time.time() + timeout
            seen = []
            while time.time() < deadline:
                r = client.get(f"/api/v1/deposit/{op_id}", headers=headers)
                assert r.status_code == 200, r.text
                data = r.json()
                if data["status"] not in seen:
                    seen.append(data["status"])
                if data["status"] == target:
                    return data
                time.sleep(0.05)
            raise AssertionError(
                f"{op_id} never reached {target!r}; saw {seen}"
            )

        def ws_session(op_id: str, auth_token: str | None = None):
            import websockets.sync.client as ws_client
            tok = auth_token if auth_token is not None else token
            ws = ws_client.connect(
                f"ws://{HOST}:{API_PORT}/ws/deposits/{op_id}?token={tok}"
            )
            first = ws.recv()
            return ws, first

        # =========================================================================
        # Scenario A — VALID plastic: full real chain + WebSocket + real AI.
        # =========================================================================

        # WS auth gate: a bad token must be refused before any message flows.
        import json as _json
        bad_rejected = False
        try:
            ws_bad, _ = ws_session("anything", auth_token="totally-wrong-token")
            ws_bad.close()
        except Exception:
            bad_rejected = True
        record("WS auth gate rejects a bad token", bad_rejected)

        start = points_now()
        control.plan = DepositPlan(name="valid-plastic")
        pred = predict_fixture("high_conf_plastic.png")
        assert pred["predicted_class"] == "plastic", pred
        assert pred["source"] == "ai", pred  # real trained model, not demo
        assert pred["confidence"] >= 0.80, pred  # auto-routable
        record("Real AI: plastic image -> plastic, source=ai", pred["source"] == "ai")

        session = create_session(pred["prediction_id"])
        op_a = session["operation_id"]

        ws_a, first_a = ws_session(op_a)
        ws_messages = [first_a]
        assert isinstance(first_a, str), first_a
        assert _json.loads(first_a)["type"] == "subscribed"
        record("WS subscribed before terminal", True)

        done = wait_status(op_a, "confirmed")
        # Drain the socket: it must deliver state frames and a terminal frame.
        states = []
        terminal_seen = False
        for _ in range(40):
            try:
                msg = ws_a.recv(timeout=0.5)
            except Exception:
                break
            ws_messages.append(msg)
            obj = _json.loads(msg)
            if obj.get("type") == "state":
                states.append(obj["deposit"]["status"])
            if obj.get("type") == "terminal":
                terminal_seen = True
                assert obj["deposit"]["status"] == "confirmed", obj
                assert obj["deposit"]["points_awarded"] == 5, obj
        ws_a.close()

        record("WS delivers live state frames", bool(states), f"states={states}")
        record("WS terminal frame carries confirmed +5", terminal_seen)

        assert done["status"] == "confirmed", done
        assert done["points_awarded"] == 5, done
        assert done["actual_position"] == 1, done
        assert done["weight_g"] > 0, done
        record("HTTP poll shows confirmed +5 pts / pos 1", True)
        record("Points +5 exactly", points_now() == start + 5,
               f"start={start} now={points_now()}")

        history = client.get("/api/v1/waste/history", headers=headers).json()["items"]
        ev_a = [e for e in history if e["operation_id"] == op_a]
        record("Audit row exists (5 pts)", bool(ev_a) and ev_a[0]["points_awarded"] == 5)
        record("Route command carried mode=automatic",
               any(c.get("mode") == "automatic" for c in control.received))

        # =========================================================================
        # Scenario B — WRONG POSITION: machine settles at compartment 2.
        # =========================================================================
        start = points_now()
        control.plan = DepositPlan(name="wrong-position", destination_position=2, actual_position=2)
        pred = predict_fixture("high_conf_plastic.png")
        session = create_session(pred["prediction_id"])
        data = wait_status(session["operation_id"], "rejected")
        record("Wrong-position rejected", "wrong_position" in data["reject_reason"], data["reject_reason"])
        record("Wrong-position awarded 0", data["points_awarded"] == 0)
        record("Wrong-position no point delta", points_now() == start)

        # =========================================================================
        # Scenario C — UNDERWEIGHT: only 0.5g hits the load cell.
        # =========================================================================
        start = points_now()
        control.plan = DepositPlan(
            name="underweight",
            weight_timeline=[(0.0, 0.0), (0.8, 0.3), (1.4, 0.5)],
            final_weight=0.5,
            emit_machine_status="underweight",
        )
        pred = predict_fixture("high_conf_plastic.png")  # routing irrelevant here
        session = create_session(pred["prediction_id"])
        data = wait_status(session["operation_id"], "rejected")
        record(
            "Underweight rejected",
            "below the minimum" in data["reject_reason"], data["reject_reason"],
        )
        record("Underweight awarded 0", data["points_awarded"] == 0)
        record("Underweight no point delta", points_now() == start)

        # =========================================================================
        # Scenario D — EXPIRED: terminal arrives after the session lapsed.
        # =========================================================================
        start = points_now()
        control.plan = DepositPlan(name="expired")
        control.hold_seconds = 1.0
        pred = predict_fixture("high_conf_plastic.png")
        session = create_session(pred["prediction_id"])
        _force_expire(session["operation_id"])  # session lapses before terminal
        data = wait_status(session["operation_id"], "expired")
        control.hold_seconds = 0.0
        record("Expired -> status 'expired'", data["status"] == "expired", str(data))
        record("Expired awarded 0", data["points_awarded"] == 0)
        record("Expired no point delta", points_now() == start)

        # =========================================================================
        # Scenario E — CANCELLED: user cancels before the machine finishes.
        # =========================================================================
        start = points_now()
        control.plan = DepositPlan(name="cancelled")  # machine still completes
        control.hold_seconds = 0.6
        pred = predict_fixture("high_conf_plastic.png")
        session = create_session(pred["prediction_id"])
        r = client.post(f"/api/v1/deposit/{session['operation_id']}/cancel", headers=headers)
        assert r.status_code == 200, r.text
        data = wait_status(session["operation_id"], "cancelled")
        time.sleep(1.0)  # give the late terminal a chance to double-award
        control.hold_seconds = 0.0
        record("Cancel mid-flow -> cancelled", data["status"] == "cancelled")
        record("Late terminal did not award points", points_now() == start,
               f"start={start} now={points_now()}")

        # =========================================================================
        # Scenario F — DUPLICATE terminal: exactly one award.
        # =========================================================================
        start = points_now()
        control.plan = DepositPlan(name="duplicate", duplicate_terminal=True)
        pred = predict_fixture("high_conf_plastic.png")
        session = create_session(pred["prediction_id"])
        data = wait_status(session["operation_id"], "confirmed")
        time.sleep(0.5)  # second identical event must be ignored
        record("Duplicate -> confirmed +5 once", data["points_awarded"] == 5)
        record("Duplicate no double award", points_now() == start + 5,
               f"start={start} now={points_now()}")

        # =========================================================================
        # Scenario G — LOW CONFIDENCE: the real model is genuinely unsure, so
        # the backend refuses to route (real AI, no force overrides).
        # =========================================================================
        control.hold_seconds = 0.0
        control.plan = None

        pred = predict_fixture("low_conf.png")
        assert pred["confidence"] < 0.50, pred  # considered too weak to route
        r = client.post(
            "/api/v1/deposit/session", headers=headers,
            json={"ai_prediction_id": pred["prediction_id"], "station_id": "st-001"},
        )
        record(
            "Low confidence refused to route (422)",
            r.status_code == 422, f"status={r.status_code} {r.text}",
        )

        # =========================================================================
        # Scenario H — MEDIUM CONFIDENCE: real model straddles the band, backend
        # routes in manual mode and never auto-awards.
        # =========================================================================
        start = points_now()
        pred = predict_fixture("medium_conf.png")
        assert 0.50 <= pred["confidence"] < 0.80, pred
        before_routes = len(control.received)
        session = create_session(pred["prediction_id"])
        control.plan = None  # the physical drop never happens
        time.sleep(0.3)
        route = [c for c in control.received[before_routes:] if c.get("operation_id") == session["operation_id"]]
        record(
            "Medium route published in manual mode",
            bool(route) and route[0].get("mode") == "manual", str(route),
        )
        record(
            "No physical event -> no points (HTTP cannot award)",
            points_now() == start, f"start={start} now={points_now()}",
        )
        cur = client.get(f"/api/v1/deposit/{session['operation_id']}", headers=headers).json()
        record(
            "Medium session still pending (awaiting physical drop)",
            cur["status"] == "pending", str(cur["status"]),
        )

        # =========================================================================
        # Final DB integrity sweep.
        # =========================================================================
        conn = _connect_pg()
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM deposit_sessions")
            n_sessions = cur.fetchone()[0]
            cur.execute(
                "SELECT status, COUNT(*) FROM deposit_sessions GROUP BY status"
            )
            by_status = dict(cur.fetchall())
            cur.execute(
                "SELECT COUNT(*) FROM waste_events WHERE points_awarded > 0"
            )
            n_paid = cur.fetchone()[0]
            cur.execute(
                "SELECT COUNT(*) FROM deposit_sessions WHERE status='confirmed'"
            )
            n_confirmed = cur.fetchone()[0]
            cur.execute("SELECT points FROM users WHERE email=%s", (DEMO_EMAIL,))
            final_points = cur.fetchone()[0]
            cur.execute(
                "SELECT COUNT(*) FROM (SELECT operation_id FROM waste_events "
                "GROUP BY operation_id HAVING COUNT(*) > 1) AS dup"
            )
            n_dup_events = cur.fetchone()[0]
        conn.close()

        # A: +5, F: +5 -> exactly two paid events, two confirmed sessions.
        record(
            "DB: exactly 2 confirmed sessions / 2 paid waste events",
            n_confirmed == 2 and n_paid == 2,
            f"confirmed={n_confirmed} paid={n_paid} by_status={by_status}",
        )
        record("DB: no duplicated waste_events", n_dup_events == 0)
        record(
            "DB: final points = 45 + 5 + 5 = 55",
            final_points == 55, f"points={final_points}",
        )
        record(
            "DB: 7 deposit sessions on record (G=422 never created one)",
            n_sessions == 7, f"n={n_sessions}",
        )

        print()
        print("=" * 70)
        for line in results:
            print(line)
        print("=" * 70)
        print(f"RESULT: {passes} passed, {failures} failed")
        client.close()
        sys.exit(1 if failures else 0)

    finally:
        for proc in procs:
            if proc.poll() is None:
                proc.terminate()
        for proc in procs:
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()


if __name__ == "__main__":
    main()
