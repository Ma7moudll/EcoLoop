"""Rotary V2 unit tests — calibration layer, mechanical model, safety."""
from __future__ import annotations

import pytest

from hardware.rotary import (
    BIN_NAMES,
    BinMap,
    BinMapConfig,
    RotaryChute,
    RotaryChuteConfig,
    RotaryFillLevel,
    RotaryJamError,
)


# ---------------------------------------------------------------------------
# BinMap — angle/step calibration (§10: no raw steps in the state machine)
# ---------------------------------------------------------------------------

class TestBinMap:
    def test_default_four_positions_at_90_degrees(self):
        m = BinMap()
        assert [m.targets[b].position for b in BIN_NAMES] == [1, 2, 3, 4]
        assert [m.targets[b].angle_deg for b in BIN_NAMES] == [0.0, 90.0, 180.0, 270.0]

    def test_steps_conversion_matches_geometry(self):
        cfg = BinMapConfig(steps_per_revolution=200, microstepping=16, gear_ratio=1.0)
        m = BinMap(cfg)
        assert m.config.degrees_per_step == pytest.approx(360.0 / 3200.0)
        # 90° = quarter revolution = 800 microsteps
        assert m.angle_to_steps(90.0) == 800
        assert m.steps_for_angle(0.0, 90.0) == 800

    def test_shortest_path_never_swinging_270(self):
        m = BinMap()
        # From METAL(90°) to PLASTIC(0°) is -90°, not +270°.
        assert m.shortest_delta(90.0, 0.0) == -90.0
        assert m.steps_for_angle(90.0, 0.0) == -800
        # Wrap-around: 270° -> 0° is +90° through north.
        assert m.shortest_delta(270.0, 0.0) == 90.0

    def test_recalibration_without_rewriting_logic(self):
        """§10: a different physical layout is only new config values."""
        custom = BinMap(
            BinMapConfig(bin_angles_deg=(45.0, 135.0, 225.0, 315.0)),
            assignments={"METAL": 0, "PLASTIC": 1, "OTHER": 2, "PAPER": 3},
        )
        assert custom.target_for_position(1).bin == "METAL"
        assert custom.target_for_position(1).angle_deg == 45.0

    def test_invalid_assignments_rejected(self):
        with pytest.raises(ValueError):
            BinMap(assignments={"PLASTIC": 0, "METAL": 0, "PAPER": 2, "OTHER": 3})


# ---------------------------------------------------------------------------
# RotaryChute — homing, routing, jam, timeout (§11, §25)
# ---------------------------------------------------------------------------

def _chute(**kwargs) -> RotaryChute:
    return RotaryChute(config=RotaryChuteConfig(rotation_time_per_90_deg=0.0), **kwargs)


class TestHoming:
    def test_homing_sets_reference(self):
        c = _chute(initial_angle_deg=137.0)
        assert not c.is_homed
        list(c.home())
        assert c.is_homed
        assert c.angle_deg == 0.0
        assert c.mechanism_position() == 1  # PLASTIC at home

    def test_routing_before_homing_refused(self):
        c = _chute()
        with pytest.raises(RuntimeError):
            list(c.route_to_position(2))


class TestRouting:
    def test_route_to_each_bin_lands_on_target_angle(self):
        for position, expected_angle in [(1, 0.0), (2, 90.0), (3, 180.0), (4, 270.0)]:
            c = _chute()
            list(c.home())
            list(c.route_to_position(position))
            assert c.angle_deg % 360.0 == expected_angle
            assert c.mechanism_position() == position

    def test_idempotent_route_is_noop(self):
        """§21: route to the current bin must not physically move again."""
        c = _chute()
        list(c.home())
        moves = list(c.route_to_position(1))
        assert moves == []  # already at home

    def test_jam_detected_mid_rotation(self):
        c = _chute(jam_at_angle=45.0)
        list(c.home())
        with pytest.raises(RotaryJamError):
            list(c.route_to_position(2))  # 0° -> 90° crosses the 45° mark
