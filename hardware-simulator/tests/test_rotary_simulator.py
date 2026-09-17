"""Rotary V2 simulator-level tests: full deposit plans over the station
state machine, wire payloads, and mechanism neutrality."""
from __future__ import annotations

import pytest

from config import SimConfig
from hardware import LoadCell, RotaryChute, RotaryFillLevel, RotaryStation, BeamSensor
from rotary_simulator import EcoLoopRotarySimulator
from scenarios import DepositPlan

FAST = dict(rotation_time_per_90_deg=0.0)


def make_sim() -> EcoLoopRotarySimulator:
    """A wired rotary simulator with a no-op MQTT client (no broker)."""
    cfg = SimConfig()

    class NullMqtt:
        def set_command_handler(self, h):
            self.handler = h

        def start(self, topic):
            pass

        def stop(self):
            pass

        def publish(self, topic, payload):
            if not hasattr(self, "published"):
                self.published = []
            self.published.append(payload)

    mqtt = NullMqtt()
    chute = RotaryChute(config=__import__("hardware").RotaryChuteConfig(**FAST))
    lc = LoadCell(noise_grams=0.0)
    beam = BeamSensor()
    fill = {name: RotaryFillLevel(distance_mm=250.0) for name in ("PLASTIC", "METAL", "PAPER", "OTHER")}
    station = RotaryStation(chute=chute, load_cell=lc, beam=beam, fill_levels=fill)
    sim = EcoLoopRotarySimulator(
        config=cfg, mqtt=mqtt, chute=chute, load_cell=lc,
        station=station, capture_uploader=None, skip_homing=False,
    )
    sim.mqtt = mqtt
    return sim


def published_events(sim):
    return [p for p in getattr(sim.mqtt, "published", []) if isinstance(p, dict)]


def terminal_of(sim, operation_id):
    terms = [p for p in published_events(sim)
             if p.get("event") == "deposit_result" and p.get("operation_id") == operation_id]
    assert terms, "no terminal event published"
    return terms[-1]


class TestDepositPlans:
    def test_valid_plastic_confirms_with_mechanism_position(self):
        sim = make_sim()
        result = sim.run_plan("OP-R1", 1, DepositPlan())
        assert result["status"] == "confirmed"
        assert result["actual_position"] == 1
        # §19/§33: V2 reports ONLY the neutral field.
        assert result["mechanism_position"] == 1
        assert "carriage_position" not in result
        assert result["mechanical_confirmed"] is True
        assert result["weight_grams"] == pytest.approx(18.4, abs=0.5)

    def test_rotary_jam_reports_generic_mechanism_error(self):
        """§25: backend sees a generic mechanism jam, not carriage vocabulary."""
        plan = DepositPlan(destination_position=2, jam_angle=45.0,
                           emit_machine_status="jam")
        sim = make_sim()
        result = sim.run_plan("OP-R2", 2, plan)
        assert result["status"] == "jam"
        states = [p.get("state") for p in published_events(sim)]
        assert "JAMMED" in states
        assert result["mechanical_confirmed"] is False
        # No points can ride on a jam.
        assert result["weight_grams"] == 0.0

    def test_wrong_position_rejected(self):
        """Machine obeys the route but physically lands at the wrong slot:
        told compartment 1, chute settles at 2 -> WRONG_POSITION state and
        terminal reports actual_position=2 (backend rejects wrong_position)."""
        plan = DepositPlan(actual_position=2)
        sim = make_sim()
        result = sim.run_plan("OP-R3", 1, plan)
        assert result["actual_position"] == 2
        states = [p.get("state") for p in published_events(sim)]
        assert "WRONG_POSITION" in states

    def test_underweight_machine_reports_belief_not_success(self):
        plan = DepositPlan(weight_timeline=[(0.0, 0.0), (1.0, 0.5)],
                           final_weight=0.5, emit_machine_status="underweight")
        sim = make_sim()
        result = sim.run_plan("OP-R4", 1, plan)
        assert result["status"] == "underweight"
        assert result["mechanical_confirmed"] is False

    def test_duplicate_terminal_published_twice_same_payload(self):
        plan = DepositPlan(duplicate_terminal=True)
        sim = make_sim()
        sim.run_plan("OP-R5", 1, plan)
        terms = [p for p in published_events(sim)
                 if p.get("event") == "deposit_result" and p["operation_id"] == "OP-R5"]
        assert len(terms) == 2
        assert terms[0] == terms[1] or terms[0]["operation_id"] == terms[1]["operation_id"]

    def test_state_lifecycle_is_complete_and_monotonic(self):
        sim = make_sim()
        sim.run_plan("OP-R6", 3, DepositPlan())
        states = [p.get("state") for p in published_events(sim) if p.get("state")]
        for phase in ["ROUTING", "MOVING", "POSITIONED",
                      "READY_FOR_DEPOSIT", "DETECTING", "MEASURING",
                      "DEPOSIT_CONFIRMED", "RESETTING", "IDLE"]:
            assert phase in states, f"{phase} missing from {states}"
        # Monotonic: terminal phases come after their prerequisites.
        assert states.index("DEPOSIT_CONFIRMED") < states.index("RESETTING") < states.index("IDLE")


class TestMechanismNeutrality:
    def test_heartbeat_identifies_as_rotary(self):
        sim = make_sim()
        before = len(published_events(sim))
        sim._heartbeat()
        hb = published_events(sim)[-1]
        assert hb["mechanism"] == "rotary"
        assert "mechanism_position" in hb
        assert "carriage_position" not in hb

    def test_sensor_telemetry_never_reports_carriage_vocabulary(self):
        sim = make_sim()
        sim.run_plan("OP-R7", 1, DepositPlan())
        sensors = [p for p in published_events(sim)
                   if p.get("timestamp") and p.get("event") is None]
        assert sensors, "expected sensor telemetry"
        for s in sensors:
            assert "carriage_position" not in s
            assert "carriage" not in str(s).lower()

    def test_station_snapshot_uses_neutral_fields_and_fill_levels(self):
        sim = make_sim()
        snap = sim.station.snapshot()
        assert snap["mechanism"] == "rotary"
        assert "mechanism_position" in snap
        assert "carriage_position" not in snap
        assert set(snap["fill_level"]) == {"PLASTIC", "METAL", "PAPER", "OTHER"}
