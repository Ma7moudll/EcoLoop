"""Start the REAL service stack for the on-device Android camera E2E.

This is the host-side companion to the mobile integration test
(`mobile/integration_test/android_camera_e2e_test.dart`). It starts:

  * mosquitto broker           (port 1884)
  * ai-service (real model)    (port 8051)
  * backend + PostgreSQL       (port 8080, MQTT -> broker, AI -> ai-service)

with `DEBUG_IMAGE_HASH=true` so the debug byte-identity fingerprint route is
mounted (it is NOT mounted in normal/non-debug builds). The stack keeps
running so the emulator/device integration test can talk to it; Ctrl-C tears it
down.

    scripts/android_camera_e2e_stack.py

Prerequisites: PostgreSQL on localhost:5432 (role recycle/recycle,
db recycle_vision_e2e), mosquitto at /opt/homebrew/sbin/mosquitto, free ports
1884/8051/8080. The easiest DB bootstrap is:

    docker compose -f infra/docker-compose.yml up -d db
    createdb -U recycle recycle_vision_e2e      # then run the e2e once to create schema
"""
from __future__ import annotations

import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PYTHON = str(ROOT / ".venv" / "bin" / "python")
MOSQUITTO_BIN = Path("/opt/homebrew/sbin/mosquitto")
AI_MODEL_PATH = ROOT / "ai-service" / "models" / "model.onnx"

HOST = "0.0.0.0"  # reachable from the emulator AND from LAN devices
BIND = "127.0.0.1"
MQTT_PORT = 1884
AI_PORT = 8051
API_PORT = 8080

DB_URL = (
    "postgresql+psycopg2://recycle:recycle@localhost:5432/recycle_vision_e2e"
)
JWT_SECRET = "e2e-secret-not-for-prod"

DEMO_EMAIL = "demo@recycle.vision"
DEMO_PASSWORD = "demo123"


def _port_free(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.3)
        return s.connect_ex((HOST, port)) != 0


def _wait_port(port: int, bind: str, timeout: float = 30.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.3)
            if s.connect_ex((bind, port)) == 0:
                return
        time.sleep(0.2)
    raise RuntimeError(f"port {port} never came up")


def main() -> None:
    assert MOSQUITTO_BIN.exists(), f"mosquitto not found at {MOSQUITTO_BIN}"
    assert AI_MODEL_PATH.exists(), f"trained model not found at {AI_MODEL_PATH}"
    for p in (MQTT_PORT, AI_PORT, API_PORT):
        if not _port_free(p):
            raise SystemExit(f"port {p} busy — stop the running service")

    procs: list[subprocess.Popen] = []
    try:
        # -- mosquitto ----------------------------------------------------------
        conf = tempfile.NamedTemporaryFile(mode="w", suffix=".conf", delete=False)
        conf.write(
            f"listener {MQTT_PORT} 0.0.0.0\n"
            "allow_anonymous true\n"
            "max_queued_messages 1000\n"
            "message_size_limit 0\n"
        )
        conf.close()
        procs.append(subprocess.Popen(
            [str(MOSQUITTO_BIN), "-c", conf.name, "-v"],
            stdout=open("/tmp/android_e2e_mosquitto.log", "w"),
            stderr=subprocess.STDOUT,
        ))
        _wait_port(MQTT_PORT, "127.0.0.1")
        print(f"[stack] mosquitto listening on :{MQTT_PORT}")

        # -- ai-service (REAL model) ---------------------------------------------
        env = dict(os.environ)
        env.update({
            "PYTHONPATH": str(ROOT / "ai-service"),
            "AI_SERVICE_CLASSIFIER": "real",
            "AI_MODEL_PATH": str(AI_MODEL_PATH),
            # Poison dev overrides to prove the real path ignores them.
            "DEVELOPMENT_FORCE_CLASS": "plastic",
            "DEVELOPMENT_FORCE_CONFIDENCE": "0.99",
        })
        procs.append(subprocess.Popen(
            [PYTHON, "-m", "uvicorn", "app.main:app", "--host", BIND,
             "--port", str(AI_PORT), "--log-level", "warning"],
            cwd=str(ROOT / "ai-service"), env=env,
            stdout=open("/tmp/android_e2e_ai.log", "w"),
            stderr=subprocess.STDOUT,
        ))
        _wait_port(AI_PORT, BIND)
        print(f"[stack] ai-service on {BIND}:{AI_PORT} (classifier=real)")

        # -- backend -------------------------------------------------------------
        env = dict(os.environ)
        env.update({
            "PYTHONPATH": str(ROOT / "backend"),
            "DATABASE_URL": DB_URL,
            "MQTT_BROKER_HOST": "127.0.0.1",
            "MQTT_BROKER_PORT": str(MQTT_PORT),
            "AI_SERVICE_URL": f"http://{BIND}:{AI_PORT}",
            "JWT_SECRET": JWT_SECRET,
            "SEED_ON_STARTUP": "true",
            "DEBUG": "false",
            # Mount the byte-identity fingerprint route used by the on-device
            # camera E2E. Debug-only — absent from normal builds.
            "DEBUG_IMAGE_HASH": "true",
        })
        procs.append(subprocess.Popen(
            [PYTHON, "-m", "uvicorn", "app.main:app", "--host", HOST,
             "--port", str(API_PORT), "--log-level", "info"],
            cwd=str(ROOT / "backend"), env=env,
            stdout=open("/tmp/android_e2e_backend.log", "w"),
            stderr=subprocess.STDOUT,
        ))
        _wait_port(API_PORT, HOST)
        print(f"[stack] backend on {HOST}:{API_PORT} (DEBUG_IMAGE_HASH=true)")

        print()
        print("Services are running. From the Android EMULATOR the app reaches")
        print("them via API_BASE_URL=http://10.0.2.2:8080/api/v1; from a physical")
        print("device use this machine's LAN IP instead. Press Ctrl-C to stop.")
        print()
        try:
            while True:
                time.sleep(3600)
        except KeyboardInterrupt:
            print("[stack] shutting down")
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
    sys.exit(main())