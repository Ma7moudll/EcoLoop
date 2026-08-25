"""Full-chain integration test for ROTARY V2 — same logical flow as the
Carriage V1 suite (test_mqtt_deposit_flow.py), proving the backend treats
both mechanisms identically:

    FastAPI ──route command──▶ MQTT broker ◀─subscribe── EcoLoopRotarySimulator
    backend ◀──── deposit_result (mechanism_position) ────────── simulator

Requires a local mosquitto broker (skipped when unavailable).
"""
from __future__ import annotations

import sys
import time

import pytest

BROKER_HOST = "127.0.0.1"
BROKER_PORT = 1884
BROKER_USER = "backend"
BROKER_PASS = "itest-broker-pass"

SIM_PATH = "/Users/mac/Desktop/ECO/recycle-vision/hardware-simulator"


@pytest.fixture
def rotary_simulator(broker):
    """A real Rotary V2 simulator connected to the real broker."""
    sys.path.insert(0, SIM_PATH)

    os_env_cleanup = None
    from config import SimConfig
    from hardware import LoadCell, RotaryChute, RotaryChuteConfig, RotaryStation, BeamSensor, RotaryFillLevel
    from mqtt_client import SimulatorMqttClient
    from rotary_simulator import EcoLoopRotarySimulator

    cfg = SimConfig()
    cfg.broker_host = BROKER_HOST
    cfg.broker_port = BROKER_PORT
    cfg.mqtt_username = BROKER_USER
    cfg.mqtt_password = BROKER_PASS

    mqtt = SimulatorMqttClient(
        BROKER_HOST, BROKER_PORT,
        client_id="sim-rotary-st-001-itest",
        username=BROKER_USER, password=BROKER_PASS,
    )
    chute = RotaryChute(config=RotaryChuteConfig())
    fill = {n: RotaryFillLevel(distance_mm=200.0)
            for n in ("PLASTIC", "METAL", "PAPER", "OTHER")}
    station = RotaryStation(chute=chute,
                            load_cell=LoadCell(noise_grams=0, seed=7),
                            beam=BeamSensor(), fill_levels=fill)
    sim = EcoLoopRotarySimulator(
        config=cfg, mqtt=mqtt, chute=chute, load_cell=station.load_cell,
        station=station, capture_uploader=None,
    )
    sim.mqtt.set_command_handler(sim._on_command)
    sim.mqtt.start(cfg.command_topic())
    assert sim.mqtt.connected.wait(10), "rotary simulator did not connect to broker"
    time.sleep(0.5)  # subscription ack before the backend publishes
    yield sim
    sim.mqtt.stop()


@pytest.fixture
def gateway_connected():
    from app.state import get_gateway

    gw = get_gateway()
    assert gw is not None
    assert gw.wait_connected(15), "backend MQTT gateway did not connect to broker"
    return gw


def _wait_for_status(client, auth, operation_id, status, timeout=20.0) -> dict:
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        r = client.get(f"/api/v1/deposit/{operation_id}", headers=auth)
        if r.status_code == 200:
            last = r.json()
            if last["status"] == status:
                return last
        time.sleep(0.2)
    raise AssertionError(f"deposit {operation_id} never reached {status!r}: {last}")


def test_rotary_full_chain_mqtt_deposit_awards_points(
    client, auth, demo_session, rotary_simulator, gateway_connected, monkeypatch
):
    """The §34 acceptance flow over MQTT with mechanism=rotary:
    predict → session → route → chute rotates → deposit_result → points."""
    from app.routers import ai as ai_router
    from app.services.predict_service import PredictService
    from tests.conftest import FakeAi

    monkeypatch.setattr(
        ai_router, "PredictService", lambda: PredictService(ai=FakeAi("plastic", 0.95))
    )

    pred = client.post(
        "/api/v1/ai/predict",
        headers=auth,
        files={"image": ("capture.jpg", b"fake-jpeg-bytes", "image/jpeg")},
    )
    assert pred.status_code == 200, pred.text
    prediction = pred.json()

    r = client.post(
        "/api/v1/deposit/session",
        headers=auth,
        json={"ai_prediction_id": prediction["prediction_id"], "station_id": "st-001"},
    )
    assert r.status_code == 200, r.text
    operation_id = r.json()["operation_id"]

    confirmed = _wait_for_status(client, auth, operation_id, "confirmed")
    assert confirmed["actual_position"] == 1
    assert confirmed["points_awarded"] == 5
    assert confirmed["weight_g"] > 0

    me = client.get("/api/v1/users/me", headers=auth).json()["user"]
    assert me["points"] == 45 + 5


def test_rotary_jam_rejected_no_points(
    client, auth, demo_session, rotary_simulator, gateway_connected, monkeypatch
):
    """A jammed chute produces a generic `jam` terminal; the backend rejects
    and awards nothing (§25)."""
    from scenarios import DepositPlan

    from app.routers import ai as ai_router
    from app.services.predict_service import PredictService
    from tests.conftest import FakeAi

    monkeypatch.setattr(
        ai_router, "PredictService", lambda: PredictService(ai=FakeAi("metal", 0.97))
    )
    pred = client.post(
        "/api/v1/ai/predict",
        headers=auth,
        files={"image": ("capture.jpg", b"fake-jpeg-bytes", "image/jpeg")},
    )
    prediction = pred.json()

    # Route to METAL with a jam at 45°. Neutralize the live command handler
    # first so only our scripted jam plan executes.
    rotary_simulator.mqtt.set_command_handler(lambda cmd: None)
    plan = DepositPlan(jam_angle=45.0, emit_machine_status="jam")
    r = client.post(
        "/api/v1/deposit/session",
        headers=auth,
        json={"ai_prediction_id": prediction["prediction_id"], "station_id": "st-001"},
    )
    operation_id = r.json()["operation_id"]
    destination = int(prediction["destination_position"])
    time.sleep(0.5)  # let the (now ignored) route command arrive first
    rotary_simulator.run_plan(operation_id, destination, plan)

    rejected = _wait_for_status(client, auth, operation_id, "rejected")
    assert 'jam' in rejected["reject_reason"]
    me = client.get("/api/v1/users/me", headers=auth).json()["user"]
    assert me["points"] == 45  # unchanged — no points without physics
