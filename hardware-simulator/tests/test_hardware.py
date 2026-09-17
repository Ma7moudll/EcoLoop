"""Rotary chute, sensors, load cell and state machine unit tests."""
from __future__ import annotations

import pytest

from hardware import (
    BeamSensor,
    BinMap,
    IllegalTransition,
    LoadCell,
    MachineState,
    RotaryChute,
    RotaryChuteConfig,
    RotaryJamError,
    StateMachine,
    settle_profile,
)


# -- BinMap ----------------------------------------------------------------------

class TestBinMap:
    def test_target_for_each_position(self):
        m = BinMap()
        for pos, angle in ((1, 0.0), (2, 90.0), (3, 180.0), (4, 270.0)):
            t = m.target_for_position(pos)
            assert t.position == pos
            assert t.angle_deg == angle

    def test_shortest_delta_takes_shortest_path(self):
        m = BinMap()
        assert m.shortest_delta(0.0, 90.0) == 90.0
        assert m.shortest_delta(0.0, 270.0) == -90.0  # 270° CCW is shorter than CW


# -- Rotary chute ----------------------------------------------------------------

class TestRotaryChute:
    def _chute(self) -> RotaryChute:
        return RotaryChute(config=RotaryChuteConfig(rotation_time_per_90_deg=0.0))

    def test_home_arrives_at_zero(self):
        c = self._chute()
        list(c.home())
        assert c.mechanism_position() == 1

    def test_route_to_position_reports_target(self):
        c = self._chute()
        list(c.home())
        list(c.route_to_position(3))
        assert c.mechanism_position() == 3

    def test_route_takes_shortest_path(self):
        c = self._chute()
        list(c.home())
        moved = list(c.route_to_position(4))
        assert len(moved) > 0

    def test_invalid_position_rejected(self):
        c = self._chute()
        list(c.home())
        with pytest.raises(KeyError):
            list(c.route_to_position(9))

    def test_jam_raises_mid_rotation(self):
        c = RotaryChute(config=RotaryChuteConfig(), jam_at_angle=45.0)
        list(c.home())
        with pytest.raises(RotaryJamError):
            list(c.route_to_position(2))
        assert c.mechanism_position() != 2  # jammed before reaching the target


# -- Sensors -------------------------------------------------------------------

class TestSensors:
    def test_beam(self):
        b = BeamSensor()
        assert b.broken is False
        b.set(True)
        assert b.read() is True


# -- Load cell -----------------------------------------------------------------

class TestLoadCell:
    def test_set_value_and_read(self):
        cell = LoadCell(noise_grams=0, seed=1)
        cell.set_value(18.4)
        assert cell.read_weight() == 18.4

    def test_noise_keeps_reading_within_bounds(self):
        cell = LoadCell(noise_grams=0.5, seed=7)
        for _ in range(50):
            cell.set_value(10.0)
            assert -0.5 <= cell.read_weight() - 10.0 <= 0.5

    def test_settle_profile_ramps_between_breakpoints(self):
        ramp = settle_profile([(0.0, 0.0), (0.8, 4.0), (1.4, 12.0), (2.0, 18.4)])
        assert ramp(0.0) == 0.0
        assert ramp(0.4) == 2.0  # midpoint of 0->4 over 0->0.8
        assert ramp(0.8) == 4.0
        assert ramp(2.0) == 18.4
        assert ramp(5.0) == 18.4  # clamped after settle

    def test_profile_is_monotonic(self):
        ramp = settle_profile([(0.0, 0.0), (0.8, 4.0), (1.4, 12.0), (2.0, 18.4)])
        prev = -1
        for t in [i / 10 for i in range(0, 41)]:
            v = ramp(t)
            assert v >= prev
            prev = v


# -- State machine ---------------------------------------------------------------

class TestStateMachine:
    def test_happy_path(self):
        m = StateMachine()
        m.transition(MachineState.ROUTING)
        m.transition(MachineState.MOVING)
        m.transition(MachineState.POSITIONED)
        m.transition(MachineState.READY_FOR_DEPOSIT)
        m.transition(MachineState.DETECTING)
        m.transition(MachineState.MEASURING)
        m.transition(MachineState.DEPOSIT_CONFIRMED)
        m.transition(MachineState.RESETTING)
        m.transition(MachineState.IDLE)
        assert m.state == MachineState.IDLE

    def test_illegal_transition_raises(self):
        m = StateMachine()
        m.transition(MachineState.ROUTING)
        with pytest.raises(IllegalTransition):
            m.transition(MachineState.DEPOSIT_CONFIRMED)  # ROUTING -> DEPOSIT_CONFIRMED

    def test_error_states_can_reset(self):
        # Legal paths to each error state, then RESETTING -> IDLE.
        paths = {
            MachineState.JAMMED: [MachineState.ROUTING, MachineState.MOVING],
            MachineState.WRONG_POSITION: [MachineState.ROUTING, MachineState.MOVING, MachineState.POSITIONED],
            MachineState.UNDERWEIGHT: [
                MachineState.ROUTING, MachineState.MOVING, MachineState.POSITIONED,
                MachineState.READY_FOR_DEPOSIT, MachineState.DETECTING, MachineState.MEASURING,
            ],
            MachineState.SENSOR_ERROR: [MachineState.ROUTING, MachineState.MOVING, MachineState.POSITIONED, MachineState.READY_FOR_DEPOSIT, MachineState.DETECTING],
            MachineState.TIMEOUT: [MachineState.ROUTING, MachineState.MOVING],
        }
        for error_state, prefix in paths.items():
            m = StateMachine()
            for step in prefix:
                m.transition(step)
            m.transition(error_state)
            assert m.in_error()
            m.transition(MachineState.RESETTING)
            m.transition(MachineState.IDLE)

    def test_can_transition(self):
        m = StateMachine()
        assert m.can_transition(MachineState.ROUTING)
        assert not m.can_transition(MachineState.MOVING)
        assert not m.in_error()
