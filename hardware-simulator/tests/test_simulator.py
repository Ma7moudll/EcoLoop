"""End-to-end simulator scenario tests: run a DepositPlan through
`EcoLoopSimulator.run_plan` with a recording (fake) MQTT client and assert the
exact terminal deposit_result a real backend would validate."""
from __future__ import annotations

import os

os.environ["SIMULATOR_RAMP_STEP"] = "0"  # fast ramp for tests

import pytest  # noqa: E402

from config import SimConfig  # noqa: E402
from hardware import Carriage, LoadCell  # noqa: E402
from scenarios import SCENARIOS, DepositPlan  # noqa: E402
from simulator import EcoLoopSimulator  # noqa: E402


class FakeMqtt:
    def __init__(self) -> None:
        self.published: list[tuple[str, dict]] = []

    def start(self, topic):  # pragma: no cover - test double
        pass

    def stop(self):  # pragma: no cover - test double
        pass

    def set_command_handler(self, handler):  # pragma: no cover - test double
        self.handler = handler

    def publish(self, topic, payload, qos=0):
        self.published.append((topic, payload))


@pytest.fixture
def make_sim():
    def _make():
        return EcoLoopSimulator(
            config=SimConfig(),
            mqtt=FakeMqtt(),
            carriage=Carriage(initial_position=1, movement_time_per_step=0),
            load_cell=LoadCell(noise_grams=0, seed=7),
        )

    return _make


def terminals(published: list[tuple[str, dict]]) -> list[dict]:
    return [
        payload
        for topic, payload in published
        if topic.endswith("/event") and payload.get("event") == "deposit_result"
    ]


class TestValidPlastic:
    def test_terminal_fields(self, make_sim):
        sim = make_sim()
        term = sim.run_plan("OP-20260817-000001", 1, SCENARIOS["valid-plastic"])
        assert term["status"] == "confirmed"
        assert term["actual_position"] == 1
        assert term["weight_grams"] == 18.4
        assert term["weight_stable"] is True
        assert term["beam_event_seen"] is True
        assert term["mechanical_confirmed"] is True
        assert term["operation_id"] == "OP-20260817-000001"
        assert term["station_id"] == "ST-001"

    def test_machine_returns_to_idle(self, make_sim):
        sim = make_sim()
        sim.run_plan("OP-20260817-000001", 1, SCENARIOS["valid-plastic"])
        assert sim.station.state.value == "IDLE"

    def test_state_events_published_in_order(self, make_sim):
        sim = make_sim()
        sim.run_plan("OP-20260817-000001", 1, SCENARIOS["valid-plastic"])
        states = [
            payload["state"]
            for _, payload in sim.mqtt.published
            if payload.get("event") == "state_changed"
        ]
        assert "ROUTING" in states
        assert "MOVING" in states
        assert "DEPOSIT_CONFIRMED" in states
        assert states[-1] == "IDLE"


class TestWrongPosition:
    def test_terminal_reports_actual_2(self, make_sim):
        sim = make_sim()
        term = sim.run_plan("OP-20260817-000002", 1, SCENARIOS["wrong-position"])
        assert term["status"] == "confirmed"  # machine believes it succeeded
        assert term["actual_position"] == 2  # backend must catch the mismatch
        assert term["mechanical_confirmed"] is True


class TestUnderweight:
    def test_terminal_underweight(self, make_sim):
        sim = make_sim()
        term = sim.run_plan("OP-20260817-000003", 1, SCENARIOS["underweight"])
        assert term["status"] == "underweight"
        assert term["weight_grams"] == 0.5
        assert term["weight_stable"] is False  # below the minimum

    def test_machine_enters_underweight_state(self, make_sim):
        sim = make_sim()
        sim.run_plan("OP-20260817-000003", 1, SCENARIOS["underweight"])
        states = [
            payload["state"]
            for _, payload in sim.mqtt.published
            if payload.get("event") == "state_changed"
        ]
        assert "UNDERWEIGHT" in states


class TestJam:
    def test_terminal_jam(self, make_sim):
        sim = make_sim()
        term = sim.run_plan("OP-20260817-000004", 1, SCENARIOS["jam"])
        assert term["status"] == "jam"
        assert term["mechanical_confirmed"] is False
        assert term["beam_event_seen"] is False

    def test_machine_returns_to_idle_after_jam(self, make_sim):
        sim = make_sim()
        sim.run_plan("OP-20260817-000004", 1, SCENARIOS["jam"])
        assert sim.station.state.value == "IDLE"


class TestDuplicate:
    def test_two_identical_terminal_events(self, make_sim):
        sim = make_sim()
        sim.run_plan("OP-20260817-000005", 1, SCENARIOS["duplicate"])
        terms = terminals(sim.mqtt.published)
        assert len(terms) == 2
        assert terms[0]["operation_id"] == terms[1]["operation_id"] == "OP-20260817-000005"


class TestCommandDispatch:
    def test_route_command_drives_a_plan(self, make_sim):
        sim = make_sim()
        sim._on_command(
            {"command": "route", "operation_id": "OP-20260817-000006", "destination_position": 2}
        )
        terms = terminals(sim.mqtt.published)
        assert len(terms) == 1
        assert terms[0]["operation_id"] == "OP-20260817-000006"
        assert terms[0]["actual_position"] == 2  # obeyed the route command

    def test_non_route_command_ignored(self, make_sim):
        sim = make_sim()
        sim._on_command({"command": "reboot"})
        assert terminals(sim.mqtt.published) == []


def test_timeout_scenario_sleeps_before_terminal(make_sim):
    """The timeout scenario completes the deposit but the terminal fires after
    a delay — the backend (with a shorter TTL) must reject it as expired."""
    sim = make_sim()
    term = sim.run_plan("OP-20260817-000007", 1, SCENARIOS["timeout"])
    assert term["status"] == "confirmed"
    assert term["actual_position"] == 1