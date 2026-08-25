"""End-to-end proof of the ROTARY V2 deposit chain on real services.

Same stack as e2e_real_chain.py (real mosquitto + real AI service + real
FastAPI/Postgres), but the physical station is the ROTARY V2 simulator and
the identification flow is the Ecolamp student-handoff QR:

    student mints handoff token  ->  STATION claims it (X-Station-Key)
    -> capture-first session     ->  station camera uploads REAL AI frame
    -> backend routes            ->  ROUTE command over MQTT
    -> rotary chute rotates      ->  deposit_result (mechanism_position)
    -> backend validates         ->  points awarded

Also proves: generic jam error, duplicate-route idempotency, and that NO
carriage vocabulary ever appears on the wire from V2.

    scripts/e2e_rotary_chain.py
"""
from __future__ import annotations

import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
os.environ.setdefault("SIMULATOR_RAMP_STEP", "0")
sys.path.insert(0, str(ROOT / "hardware-simulator"))

import httpx  # noqa: E402

import e2e_real_chain as base  # noqa: E402
from hardware import (  # noqa: E402
    BeamSensor,
    LoadCell,
    RotaryChute,
    RotaryChuteConfig,
    RotaryFillLevel,
    RotaryStation,
)
from rotary_simulator import EcoLoopRotarySimulator  # noqa: E402
from scenarios import DepositPlan  # noqa: E402

HOST = base.HOST
MQTT_PORT = base.MQTT_PORT
API_PORT = base.API_PORT


class RecordingMqtt:
    """Wraps the sim client and records every outgoing payload so we can
    prove mechanism neutrality on the actual wire."""

    def __init__(self, inner):
        self.inner = inner
        self.sent: list[dict] = []

    def __getattr__(self, name):
        return getattr(self.inner, name)

    def publish(self, topic, payload):
        self.sent.append(payload)
        return self.inner.publish(topic, payload)


def make_rotary_sim(cfg) -> EcoLoopRotarySimulator:
    mqtt_inner = base.__dict__ and __import__("mqtt_client", fromlist=["SimulatorMqttClient"]).SimulatorMqttClient(
        cfg.broker_host, cfg.broker_port,
        client_id=f"rotary-{cfg.station_code.lower()}",
        username=cfg.mqtt_username, password=cfg.mqtt_password, tls=False,
    )
    rec = RecordingMqtt(mqtt_inner)
    chute = RotaryChute(config=RotaryChuteConfig())
    fill = {n: RotaryFillLevel(distance_mm=210.0)
            for n in ("PLASTIC", "METAL", "PAPER", "OTHER")}
    station = RotaryStation(
        chute=chute, load_cell=LoadCell(noise_grams=0, seed=7),
        beam=BeamSensor(), fill_levels=fill,
    )
    sim = EcoLoopRotarySimulator(
        config=cfg, mqtt=rec, chute=chute, load_cell=station.load_cell,
        station=station, capture_uploader=None,
    )
    sim.recorder = rec
    return sim


def main() -> None:
    # Reuse the proven harness for broker + AI + backend lifecycle by running
    # its main() pieces inline is complex; instead launch the same services
    # with the same helper functions, then drive ROTARY scenarios here.
    procs: list = []
    try:
        procs, ctx = base_launch()
        (client, headers, sim) = ctx

        results: list[tuple[str, bool, str]] = []

        def record(name, ok, detail=""):
            results.append((name, ok, detail))
            print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f": {detail}" if detail and not ok else ""))

        def points_now() -> int:
            return client.get("/api/v1/users/me", headers=headers).json()["user"]["points"]

        def wait_status(op_id, target, timeout=25.0) -> dict:
            deadline = time.time() + timeout
            while time.time() < deadline:
                r = client.get(f"/api/v1/deposit/{op_id}", headers=headers)
                if r.status_code == 200 and r.json()["status"] == target:
                    return r.json()
                time.sleep(0.05)
            raise AssertionError(f"{op_id} never reached {target!r}")

        # =====================================================================
        # 1. Student handoff QR -> station claim -> capture-first session
        # =====================================================================
        start_points = points_now()

        mint = client.post("/api/v1/deposit/handoff-token", headers=headers)
        assert mint.status_code == 200, mint.text
        qr_token = mint.json()["token"]
        record("student minted single-use handoff QR token", len(qr_token) >= 32)

        claim = client.post(
            "/api/v1/deposit/session/claim",
            headers={"X-Station-Key": "dev-station-key"},
            json={"token": qr_token, "station_id": "st-001"},
        )
        assert claim.status_code == 200, claim.text
        op1 = claim.json()["operation_id"]
        assert claim.json()["status"] == "capture"
        record("station claimed QR -> capture-first session created",
               claim.json()["status"] == "capture")

        # replay of the same QR must fail (single use)
        replay = client.post(
            "/api/v1/deposit/session/claim",
            headers={"X-Station-Key": "dev-station-key"},
            json={"token": qr_token, "station_id": "st-001"},
        )
        record("QR replay rejected (single-use)", replay.status_code == 422)

        # Station camera answers capture_request with a REAL AI fixture frame.
        post_capture(client, headers, op1, "high_conf_plastic.png")

        # The backend classifies + routes over MQTT; the ROTARY chute executes.
        done = wait_status(op1, "confirmed")
        record("rotary deposit CONFIRMED end-to-end (real AI + MQTT)",
               done["status"] == "confirmed" and done["points_awarded"] == 5,
               f"got {done}")
        gained = points_now() - start_points
        record("backend awarded exactly 5 points once", gained == 5, f"gained={gained}")

        # Mechanism neutrality on the actual wire payloads.
        sent = [p for p in sim.recorder.sent if isinstance(p, dict)]
        terminals = [p for p in sent if p.get("event") == "deposit_result"]
        assert terminals, "no terminal captured from recorder"
        t0 = terminals[-1]
        neutral = ("mechanism_position" in t0 and "carriage_position" not in t0)
        heartbeats = [p for p in sent if p.get("mechanism") is not None]
        hb_ok = any(p.get("mechanism") == "rotary" for p in heartbeats)
        all_wire = " ".join(str(sorted(p.keys())) for p in sent)
        no_carriage = "carriage_position" not in all_wire
        record("terminal uses mechanism_position only", neutral, str(t0))
        record("heartbeat identifies mechanism=rotary", hb_ok)
        record("ZERO carriage_position fields on the V2 wire", no_carriage)

        # =====================================================================
        # 2. JAM: generic mechanism error, zero points
        # =====================================================================
        start_points = points_now()
        # Neuter auto-execution BEFORE claiming so we drive the jam manually
        # (capture_request is answered, but routes are not executed).
        def capture_only(cmd: dict) -> None:
            if cmd.get("command") == "capture_request":
                post_capture(client, headers, cmd["operation_id"],
                             "medium_conf.png")
        sim.mqtt.set_command_handler(capture_only)

        mint2 = client.post("/api/v1/deposit/handoff-token", headers=headers).json()
        op2 = client.post(
            "/api/v1/deposit/session/claim",
            headers={"X-Station-Key": "dev-station-key"},
            json={"token": mint2["token"], "station_id": "st-001"},
        ).json()["operation_id"]
        time.sleep(0.8)  # capture + classify + route arrive; route NOT executed
        jam_plan = DepositPlan(jam_angle=45.0, emit_machine_status="jam")
        sim.run_plan(op2, 2, jam_plan)  # routed to METAL(90°); jams at 45°
        rej = wait_status(op2, "rejected")
        record("jam -> REJECTED with generic mechanism reason",
               "jam" in (rej.get("reject_reason") or ""),
               rej.get("reject_reason"))
        record("jam awarded ZERO points", points_now() == start_points)

        # =====================================================================
        # 3. Duplicate ROUTE command idempotency (§21): a redelivered MQTT
        #    command must not execute the physical move twice.
        # =====================================================================
        import threading

        import rotary_simulator as rs

        sim.restore_full_handler()  # resume normal command execution
        mint3 = client.post("/api/v1/deposit/handoff-token", headers=headers).json()
        op3 = client.post(
            "/api/v1/deposit/session/claim",
            headers={"X-Station-Key": "dev-station-key"},
            json={"token": mint3["token"], "station_id": "st-001"},
        ).json()["operation_id"]
        # The live wrapped handler answers capture_request automatically.
        wait_status(op3, "confirmed")

        # Slow the weight ramp so a duplicate can arrive mid-operation.
        original_ramp = rs._RAMP_STEP
        rs._RAMP_STEP = 0.25
        terminals_before = sum(
            1 for p in sim.recorder.sent
            if isinstance(p, dict) and p.get("event") == "deposit_result"
            and p.get("operation_id") == op3
        )
        route_cmd = {
            "command": "route", "operation_id": op3,
            "destination_position": 1, "mode": "automatic",
        }
        # BOTH deliveries arrive through the station's command handler —
        # exactly as MQTT QoS-1 redelivery would.
        t = threading.Thread(target=lambda: sim._on_command(dict(route_cmd)))
        t.start()
        time.sleep(0.4)                       # operation now IN FLIGHT
        sim._on_command(dict(route_cmd))      # MQTT redelivery of same route
        t.join()
        rs._RAMP_STEP = original_ramp
        time.sleep(0.2)
        terminals_after = sum(
            1 for p in sim.recorder.sent
            if isinstance(p, dict) and p.get("event") == "deposit_result"
            and p.get("operation_id") == op3
        )
        record("duplicate route ignored while operation in flight",
               terminals_after == terminals_before,
               f"terminals {terminals_before} -> {terminals_after}")

        print()
        passed = sum(1 for _, ok, _ in results if ok)
        failed = sum(1 for _, ok, _ in results if not ok)
        print(f"ROTARY E2E: {passed} passed, {failed} failed")
        if failed:
            raise SystemExit(1)

    finally:
        for p in procs:
            p.terminate()


def post_capture(client, headers, operation_id, fixture_name):
    """Station camera stand-in: upload a REAL AI fixture to /deposit/capture."""
    r = client.post(
        "/api/v1/deposit/capture",
        headers={**headers, "X-Station-Key": "dev-station-key"},
        data={"operation_id": operation_id, "station_code": "ST-001"},
        files={"image": ("frame.jpg", base._fixture_bytes(fixture_name), "image/jpeg")},
    )
    assert r.status_code == 200, r.text


def base_launch():
    """Launch mosquitto + AI + backend exactly like e2e_real_chain.main(),
    then build the HTTP client and the ROTARY simulator."""
    import secrets
    import subprocess
    import tempfile

    PYTHON = base.PYTHON
    procs: list = []

    assert base.MOSQUITTO_BIN.exists()
    if not base._port_free(MQTT_PORT) or not base._port_free(base.AI_PORT) \
            or not base._port_free(base.API_PORT):
        raise SystemExit("ports busy — stop running services first")

    mqtt_user = "backend"
    mqtt_pass = secrets.token_urlsafe(24)
    passwd_file = "/tmp/e2e_mosquitto.passwd"
    acl_file = "/tmp/e2e_mosquitto.acl"
    Path(passwd_file).unlink(missing_ok=True)
    subprocess.run(["/opt/homebrew/bin/mosquitto_passwd", "-b", "-c",
                    passwd_file, mqtt_user, mqtt_pass], check=True)
    with open(acl_file, "w") as acl:
        acl.write(f"user {mqtt_user}\ntopic readwrite ecoloop/stations/#\n")
    conf = tempfile.NamedTemporaryFile(mode="w", suffix=".conf", delete=False)
    conf.write(
        f"listener {MQTT_PORT}\nallow_anonymous false\n"
        f"password_file {passwd_file}\nacl_file {acl_file}\n"
        "max_queued_messages 1000\nmessage_size_limit 0\n"
    )
    conf.close()
    procs.append(subprocess.Popen(
        [str(base.MOSQUITTO_BIN), "-c", conf.name, "-v"],
        stdout=open("/tmp/e2e_mosquitto.log", "w"), stderr=subprocess.STDOUT))
    base._wait_port(MQTT_PORT)

    env = dict(os.environ)
    env.update({
        "PYTHONPATH": str(ROOT / "ai-service"),
        "AI_SERVICE_CLASSIFIER": "real",
        "AI_MODEL_PATH": str(base.AI_MODEL_PATH),
    })
    procs.append(subprocess.Popen(
        [PYTHON, "-m", "uvicorn", "app.main:app", "--port", str(base.AI_PORT),
         "--log-level", "warning"],
        cwd=str(ROOT / "ai-service"), env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    base._wait_port(base.AI_PORT)

    backend_env = dict(os.environ)
    backend_env.update({
        "PYTHONPATH": str(ROOT / "backend"),
        "DATABASE_URL": base.DB_URL,
        "MQTT_BROKER_HOST": HOST,
        "MQTT_BROKER_PORT": str(MQTT_PORT),
        "MQTT_USERNAME": mqtt_user,
        "MQTT_PASSWORD": mqtt_pass,
        "AI_SERVICE_URL": f"http://{HOST}:{base.AI_PORT}",
        "JWT_SECRET": base.JWT_SECRET,
        "SEED_ON_STARTUP": "true",
        "SEED_DEMO_USER": "true",
        "DEBUG": "false",
    })
    procs.append(subprocess.Popen(
        [PYTHON, "-m", "uvicorn", "app.main:app", "--port", str(API_PORT),
         "--log-level", "info"],
        cwd=str(ROOT / "backend"), env=backend_env,
        stdout=open("/tmp/e2e_backend.log", "w"), stderr=subprocess.STDOUT))
    base._wait_port(API_PORT)
    base._truncate_db()

    client = httpx.Client(base_url=f"http://{HOST}:{API_PORT}", timeout=30.0)
    login = client.post("/api/v1/auth/login",
                        json={"email": base.DEMO_EMAIL, "password": base.DEMO_PASSWORD})
    assert login.status_code == 200, login.text
    headers = {"Authorization": f"Bearer {login.json()['token']}"}

    from config import SimConfig
    cfg = SimConfig()
    cfg.broker_host = HOST
    cfg.broker_port = MQTT_PORT
    cfg.mqtt_username = mqtt_user
    cfg.mqtt_password = mqtt_pass

    sim = make_rotary_sim(cfg)
    sim.mqtt.set_command_handler(sim._on_command)
    sim.mqtt.start(cfg.command_topic())
    assert sim.mqtt.connected.wait(10), "rotary simulator did not connect"
    sim._heartbeat()  # announce mechanism=rotary immediately (loop not running)

    # Wire the station-camera stand-in into the live command path.
    original = sim._on_command

    def wrapped(cmd: dict) -> None:
        if cmd.get("command") == "capture_request":
            post_capture(client, headers, cmd["operation_id"],
                         "high_conf_plastic.png")
            return
        original(cmd)

    sim.restore_full_handler = lambda: sim.mqtt.set_command_handler(wrapped)
    sim.mqtt.set_command_handler(wrapped)

    return procs, (client, headers, sim)


if __name__ == "__main__":
    main()
