"""E2E against HiveMQ Cloud (TLS 8883) — the REAL cloud MQTT transport.

Proves the production broker path end to end: backend gateway + hardware
simulator both connect to HiveMQ Cloud over TLS with credentials from the
environment, and a real deposit round-trips through the cloud broker.

    export MQTT_HIVEMQ_HOST="<cluster>.s1.eu.hivemq.cloud"
    export MQTT_HIVEMQ_USERNAME="..."
    export MQTT_HIVEMQ_PASSWORD="..."     # secret env only, NEVER committed
    scripts/e2e_hivemq_cloud.py

Isolation: every run uses its own topic prefix `e2ecloud/<run-id>/stations/...`
so the harness never touches real station topics on the shared cluster.
Requires PostgreSQL (ecoloop_e2e), mosquitto NOT needed.
"""
from __future__ import annotations

import os
import secrets
import socket
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PYTHON = str(ROOT / ".venv" / "bin" / "python")
AI_MODEL_PATH = ROOT / "ai-service" / "models" / "model.onnx"

HOST = "127.0.0.1"
AI_PORT = 8053
API_PORT = 8083
DB_URL = "postgresql+psycopg2://ecoloop:ecoloop@localhost:5432/ecoloop_e2e"
DEMO_EMAIL = "demo@ecoloop.app"
DEMO_PASSWORD = "demo123"


def _wait_port(port: int, timeout: float = 30.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.3)
            if s.connect_ex((HOST, port)) == 0:
                return
        time.sleep(0.2)
    raise RuntimeError(f"port {port} never came up")


def main() -> None:
    host = os.environ.get("MQTT_HIVEMQ_HOST")
    username = os.environ.get("MQTT_HIVEMQ_USERNAME")
    password = os.environ.get("MQTT_HIVEMQ_PASSWORD")
    port = int(os.environ.get("MQTT_HIVEMQ_PORT", "8883"))
    if not (host and username and password):
        print(
            "NOT PROVEN: set MQTT_HIVEMQ_HOST / MQTT_HIVEMQ_USERNAME / "
            "MQTT_HIVEMQ_PASSWORD in your environment (never commit them).",
            file=sys.stderr,
        )
        return 1
    assert AI_MODEL_PATH.exists(), "trained model missing"

    prefix = f"e2ecloud/{uuid.uuid4().hex[:8]}/stations"
    procs: list[subprocess.Popen] = []
    try:
        # -- reset e2e database --------------------------------------------------
        subprocess.run([PYTHON, str(ROOT / "scripts" / "reset_dev_db.py"), "--db", "e2e"],
                       check=True, capture_output=True)

        # -- ai-service ----------------------------------------------------------
        env = dict(os.environ)
        env.update({
            "PYTHONPATH": str(ROOT / "ai-service"),
            "AI_SERVICE_CLASSIFIER": "real",
            "AI_MODEL_PATH": str(AI_MODEL_PATH),
        })
        procs.append(subprocess.Popen(
            [PYTHON, "-m", "uvicorn", "app.main:app", "--port", str(AI_PORT),
             "--log-level", "warning"],
            cwd=str(ROOT / "ai-service"), env=env,
            stdout=open("/tmp/hivemq_ai.log", "w"), stderr=subprocess.STDOUT,
        ))
        _wait_port(AI_PORT)

        # -- backend (TLS -> HiveMQ Cloud) ---------------------------------------
        backend_env = dict(os.environ)
        backend_env.update({
            "PYTHONPATH": str(ROOT / "backend"),
            "DATABASE_URL": DB_URL,
            "MQTT_BROKER_HOST": host,
            "MQTT_BROKER_PORT": str(port),
            "MQTT_TLS": "true",
            "MQTT_TOPIC_PREFIX": prefix,
            "MQTT_USERNAME": username,
            "MQTT_PASSWORD": password,
            "AI_SERVICE_URL": f"http://{HOST}:{AI_PORT}",
            "JWT_SECRET": "e2e-secret-not-for-prod",
            "SEED_ON_STARTUP": "true",
            "SEED_DEMO_USER": "true",
            "DEBUG": "false",
        })
        procs.append(subprocess.Popen(
            [PYTHON, "-m", "uvicorn", "app.main:app", "--host", HOST,
             "--port", str(API_PORT), "--log-level", "info"],
            cwd=str(ROOT / "backend"), env=backend_env,
            stdout=open("/tmp/hivemq_backend.log", "w"), stderr=subprocess.STDOUT,
        ))
        _wait_port(API_PORT)
        time.sleep(6)  # allow TLS handshake + cloud CONNECT + subscriptions

        # -- simulator (TLS -> HiveMQ Cloud) -------------------------------------
        sim_env = dict(os.environ)
        sim_env.update({
            "PYTHONPATH": str(ROOT / "hardware-simulator"),
            "MQTT_BROKER_HOST": host,
            "MQTT_BROKER_PORT": str(port),
            "MQTT_TLS": "true",
            "MQTT_TOPIC_PREFIX": prefix,
            "MQTT_USERNAME": username,
            "MQTT_PASSWORD": password,
            "BACKEND_URL": f"http://{HOST}:{API_PORT}",
            "STATION_API_KEY": "dev-station-key",
            "SIM_CAPTURE_CLASS": "plastic",
            "SIMULATOR_MOVEMENT_TIME": "0",
        })
        sim_proc = subprocess.Popen(
            [PYTHON, "-c",
             "from config import SimConfig; from rotary_simulator import EcoLoopRotarySimulator; "
             "from hardware import RotaryChute, RotaryChuteConfig, LoadCell; "
             "cfg = SimConfig(); "
             "sim = EcoLoopRotarySimulator(config=cfg, chute=RotaryChute(config=RotaryChuteConfig(rotation_time_per_90_deg=0.0)), load_cell=LoadCell(noise_grams=0, seed=7)); "
             "sim.mqtt.set_command_handler(sim._on_command); "
             "sim.mqtt.start(cfg.command_topic()); "
             "sim.mqtt.connected.wait(30); "
             "[__import__('time').sleep(1) for _ in iter(int, 1)]"],
            cwd=str(ROOT / "hardware-simulator"), env=sim_env,
            stdout=open("/tmp/hivemq_sim.log", "w"), stderr=subprocess.STDOUT,
        )
        procs.append(sim_proc)
        time.sleep(8)

        # -- drive one real deposit through the CLOUD broker ----------------------
        import httpx

        client = httpx.Client(base_url=f"http://{HOST}:{API_PORT}", timeout=30.0)
        login = client.post("/api/v1/auth/login",
                            json={"email": DEMO_EMAIL, "password": DEMO_PASSWORD})
        assert login.status_code == 200, login.text
        headers = {"Authorization": f"Bearer {login.json()['token']}"}

        pred = client.post("/api/v1/ai/predict", headers=headers,
                           files={"image": ("capture.jpg", _fixture_bytes(), "image/png")})
        assert pred.status_code == 200, pred.text
        prediction = pred.json()
        assert prediction["source"] == "ai", prediction

        session = client.post("/api/v1/deposit/session", headers=headers,
                              json={"ai_prediction_id": prediction["prediction_id"],
                                    "station_id": "st-001"})
        assert session.status_code == 200, session.text
        op_id = session.json()["operation_id"]
        print(f"[hivemq] session {op_id} routed via {host}:{port} (TLS)")

        deadline = time.time() + 60
        status = None
        while time.time() < deadline:
            cur = client.get(f"/api/v1/deposit/{op_id}", headers=headers).json()
            if cur["status"] == "confirmed":
                status = cur
                break
            time.sleep(0.5)
        assert status is not None, (
            f"{op_id} never confirmed over the cloud broker; saw {cur['status']}"
        )
        points = status["points_awarded"]
        assert points == 5, status

        me = client.get("/api/v1/users/me", headers=headers).json()["user"]
        assert me["points"] == 50, me

        print("[PASS] HiveMQ Cloud TLS: deposit confirmed over the real cloud broker (+5)")
        print(f"[PASS] points persisted server-side: {me['points']}")
        return 0
    finally:
        for proc in procs:
            if proc.poll() is None:
                proc.terminate()
        for proc in procs:
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()


def _fixture_bytes() -> bytes:
    """A real plastic frame from the curated confidence-band fixtures."""
    path = ROOT / "ai-service" / "tests" / "fixtures" / "high_conf_plastic.png"
    if not path.exists():
        raise SystemExit(f"fixture {path} missing — run the training pipeline")
    return path.read_bytes()


if __name__ == "__main__":
    sys.exit(main())
