"""Rotary Sorting Mechanism V2 — mechanical model and calibration layer.

Implements the SAME station contract as the Carriage V1 simulator
(`docs/mqtt-contract.md`) with a rotating chute instead of a moving carriage:

    ROUTE_TO(destination_position)
        -> lookup target angle (BinMap calibration table)
        -> rotate shortest path
        -> confirm position (home-relative angle)
        -> release waste (gravity)
        -> beam / load-cell verification
        -> deposit_result with `mechanism_position`

Mechanical vocabulary lives HERE ONLY — every wire payload uses the
mechanism-neutral field name `mechanism_position` (never carriage_position),
so the backend cannot tell V1 from V2 and neither can the student app.

All geometry/motor values are configuration, never scattered magic numbers:
see `BinMapConfig` / `RotaryChuteConfig`.
"""
from __future__ import annotations

import time
from collections.abc import Iterator
from dataclasses import dataclass, field

BIN_NAMES = ("PLASTIC", "METAL", "PAPER", "OTHER")


# ---------------------------------------------------------------------------
# Calibration layer — the ONLY place angles/steps exist
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class BinTarget:
    """One calibrated bin position. Angles are home-relative degrees,
    clockwise positive. Steps derive from geometry at construction time."""

    bin: str          # PLASTIC | METAL | PAPER | OTHER
    position: int     # 1..4 (backend compartment index)
    angle_deg: float  # home-relative shaft angle


@dataclass(frozen=True)
class BinMapConfig:
    steps_per_revolution: int = 200        # 1.8°/step NEMA 17
    microstepping: int = 16                # TMC2209 driver setting
    gear_ratio: float = 1.0                # direct drive
    bin_angles_deg: tuple[float, ...] = (0.0, 90.0, 180.0, 270.0)

    @property
    def steps_per_rev_shaft(self) -> float:
        return self.steps_per_revolution * self.microstepping * self.gear_ratio

    @property
    def degrees_per_step(self) -> float:
        return 360.0 / self.steps_per_rev_shaft


class BinMap:
    """PLASTIC->angle, METAL->angle, ... plus step conversions.

    Recalibration = constructing a new BinMap (or loading new values); the
    state machine and controller never touch raw steps."""

    def __init__(self, config: BinMapConfig | None = None,
                 assignments: dict[str, int] | None = None) -> None:
        self.config = config or BinMapConfig()
        assignments = assignments or {name: i for i, name in enumerate(BIN_NAMES)}
        if sorted(assignments.values()) != [0, 1, 2, 3]:
            raise ValueError("assignments must map each bin to positions 1..4 exactly once")
        self.targets: dict[str, BinTarget] = {}
        for bin_name, slot in assignments.items():
            angle = float(self.config.bin_angles_deg[slot])
            self.targets[bin_name] = BinTarget(
                bin=bin_name, position=slot + 1, angle_deg=self._norm(angle)
            )
        # position index -> BinTarget, for backend destination_position lookups
        self.by_position: dict[int, BinTarget] = {
            t.position: t for t in self.targets.values()
        }

    @staticmethod
    def _norm(angle: float) -> float:
        return round(angle % 360.0, 4)

    def target_for_position(self, position: int) -> BinTarget:
        if position not in self.by_position:
            raise KeyError(f"unknown compartment position {position!r}")
        return self.by_position[position]

    def steps_for_angle(self, current_deg: float, target_deg: float) -> int:
        """Whole motor-shaft steps from current to target along the shortest
        path (never a pointless 270° swing when 90° reaches the same slot)."""
        delta = self.shortest_delta(current_deg, target_deg)
        return int(round(delta / self.config.degrees_per_step))

    def shortest_delta(self, current_deg: float, target_deg: float) -> float:
        delta = (target_deg - current_deg) % 360.0
        if delta > 180.0:
            delta -= 360.0
        return delta

    def angle_to_steps(self, angle_deg: float) -> int:
        return int(round(self._norm(angle_deg) / self.config.degrees_per_step))


# ---------------------------------------------------------------------------
# Physical model — homing, rotation, jam, timeout
# ---------------------------------------------------------------------------

class RotaryJamError(RuntimeError):
    """Raised when the chute physically jams mid-rotation."""


@dataclass
class RotaryChuteConfig:
    # Motion profile (mirrors what firmware acceleration limits produce).
    degrees_per_second: float = 300.0      # peak slew
    homing_seek_deg_per_s: float = 60.0    # slow approach to the home sensor
    homing_backoff_deg: float = 5.0        # back off the hard stop after homing
    move_timeout_seconds: float = 6.0      # §25: never drive a stalled motor
    homing_timeout_seconds: float = 10.0
    max_rotation_without_sensor_deg: float = 450.0  # >360 => sensor missed
    # Simulated mechanics.
    rotation_time_per_90_deg: float = 0.3  # matches V1 per-position timing scale


class RotaryChute:
    """Simulated chute: absolute home-relative angle, Hall-sensor homing,
    shortest-path rotation with progress callbacks, jam injection, timeouts."""

    def __init__(self, config: RotaryChuteConfig | None = None,
                 bin_map: BinMap | None = None,
                 initial_angle_deg: float = 0.0,
                 jam_at_angle: float | None = None) -> None:
        self.config = config or RotaryChuteConfig()
        self.bin_map = bin_map or BinMap()
        self.angle_deg = self.bin_map._norm(initial_angle_deg)
        self.jam_at_angle = jam_at_angle  # None = healthy
        self.is_homed = False
        self.hall_triggered = initial_angle_deg == 0.0  # magnet sits at 0°

    # -- homing ---------------------------------------------------------------

    def home(self) -> Iterator[float]:
        """Rotate counter-clockwise towards the home hard-stop/Hall sensor,
        then settle onto exact 0°. Yields intermediate angles like real
        firmware publishes telemetry. Raises TimeoutError when the sensor
        never triggers within one full revolution plus margin (§11)."""
        travelled = 0.0
        seek_step = 2.5  # degrees per iteration (matches telemetry resolution)
        while not self.hall_triggered:
            travelled += seek_step
            if travelled > self.config.max_rotation_without_sensor_deg:
                raise TimeoutError("homing: home sensor never triggered")
            raw = self.angle_deg - seek_step
            if raw <= 0:
                # Crossed the home mark (0°/360° boundary): Hall fires here.
                self.angle_deg = 0.0
                self.hall_triggered = True
            else:
                self.angle_deg = self.bin_map._norm(raw)
            yield self.angle_deg
        # Settle onto the exact reference.
        self.angle_deg = 0.0
        self.is_homed = True
        yield 0.0

    # -- routing --------------------------------------------------------------

    def route_to_position(self, position: int) -> Iterator[float]:
        """Shortest-path rotation to a backend compartment index. Yields
        intermediate angles (~2.5° telemetry resolution); raises
        RotaryJamError on physical jam and TimeoutError if the modelled
        travel time exceeds the configured safety limit."""
        if not self.is_homed:
            raise RuntimeError("chute must be homed before routing")
        target = self.bin_map.target_for_position(position)
        delta = self.bin_map.shortest_delta(self.angle_deg, target.angle_deg)
        if abs(delta) < self.bin_map.config.degrees_per_step / 2:
            return  # already there — idempotent, no second physical action

        # §25 safety: the whole move must fit inside move_timeout_seconds at
        # the configured slew rate, otherwise refuse before moving.
        modelled_seconds = abs(delta) / max(self.config.degrees_per_second, 1e-9)
        if modelled_seconds > self.config.move_timeout_seconds:
            raise TimeoutError(
                f"route to position {position} needs {modelled_seconds:.2f}s "
                f"but timeout is {self.config.move_timeout_seconds:.2f}s"
            )

        direction = 1.0 if delta > 0 else -1.0
        total = abs(delta)
        n_steps = max(1, int(total // 2.5))
        step_deg = total / n_steps
        for _ in range(n_steps):
            next_angle = self.bin_map._norm(self.angle_deg + direction * step_deg)
            if self.jam_at_angle is not None and self._crosses(
                self.angle_deg, next_angle, self.jam_at_angle
            ):
                raise RotaryJamError(
                    f"sorting mechanism jammed near {self.jam_at_angle}° "
                    f"while routing to {position}"
                )
            self.angle_deg = next_angle
            yield self.angle_deg
        self.angle_deg = self.bin_map._norm(target.angle_deg)
        yield self.angle_deg

    def mechanism_position(self) -> int:
        """Compartment index the chute currently aligns with (1..4), or 0
        between positions — this is what wire payloads report."""
        for t in self.bin_map.targets.values():
            if abs(self.bin_map.shortest_delta(self.angle_deg, t.angle_deg)) < 1.0:
                return t.position
        return 0

    # -- helpers --------------------------------------------------------------

    @staticmethod
    def _crosses(a: float, b: float, mark: float) -> bool:
        """True when travelling a->b passes `mark` (handles wrap)."""
        def norm(x):
            return x % 360.0
        a, b, mark = norm(a), norm(b), norm(mark)
        if a <= b:
            return a < mark <= b
        return mark > a or mark <= b  # wrap-around


# ---------------------------------------------------------------------------
# Station assembly — same lifecycle as V1's Station
# ---------------------------------------------------------------------------

@dataclass
class RotaryFillLevel:
    """Per-bin ToF fill-level reading converted to percentage bands."""
    depth_mm: float = 250.0
    distance_mm: float = 250.0

    @property
    def percent(self) -> int:
        d = max(0.0, min(self.distance_mm, self.depth_mm))
        return int(round((1.0 - d / self.depth_mm) * 100))

    @property
    def band(self) -> str:
        if self.percent >= 95:
            return "FULL"
        if self.percent >= 75:
            return "NEAR_FULL"
        return "OK"


class RotaryStation:
    """One EcoLoop V2 unit: fixed four-bin ring, single rotating chute,
    per-bin load cell + fill sensor, station-side camera upstream.

    Reuses the EXACT V1 StateMachine so both mechanisms share one lifecycle;
    snapshots report `mechanism_position` (neutral) instead of any carriage
    vocabulary."""

    def __init__(self, chute: RotaryChute, load_cell, beam, fill_levels: dict[str, RotaryFillLevel] | None = None) -> None:
        from .state_machine import StateMachine

        self.chute = chute
        self.load_cell = load_cell
        self.beam = beam
        self.fill_levels = fill_levels or {}
        self.machine = StateMachine()

    @property
    def state(self):
        return self.machine.state

    # -- physical actions (mirror Station V1 API) -----------------------------

    def rotate_to(self, position: int, on_progress=None) -> None:
        from .state_machine import MachineState

        self.machine.transition(MachineState.MOVING)
        try:
            for angle in self.chute.route_to_position(position):
                if on_progress:
                    on_progress(angle)
        except (RotaryJamError, TimeoutError):
            self.machine.transition(MachineState.JAMMED)
            raise
        self.machine.transition(MachineState.POSITIONED)

    def reach_deposit_ready(self) -> None:
        from .state_machine import MachineState

        self.machine.transition(MachineState.READY_FOR_DEPOSIT)

    def start_detect(self) -> None:
        from .state_machine import MachineState

        self.machine.transition(MachineState.DETECTING)

    def start_measuring(self) -> None:
        from .state_machine import MachineState

        self.machine.transition(MachineState.MEASURING)

    def confirm_deposit(self) -> None:
        from .state_machine import MachineState

        self.machine.transition(MachineState.DEPOSIT_CONFIRMED)

    def reset(self) -> None:
        from .state_machine import MachineState

        self.machine.transition(MachineState.RESETTING)
        self.machine.transition(MachineState.IDLE)

    def snapshot(self) -> dict:
        return {
            "station_id": "station",
            "state": self.machine.state.value,
            "mechanism": "rotary",
            "mechanism_position": self.chute.mechanism_position(),
            "door_state": "CLOSED",
            "weight_grams": round(self.load_cell.read_weight(), 2),
            "weight_stable": False,
            "beam_broken": self.beam.broken,
            "fill_level": {
                name: {"percent": f.percent, "band": f.band}
                for name, f in self.fill_levels.items()
            },
        }
