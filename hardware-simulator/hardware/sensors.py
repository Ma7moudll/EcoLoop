"""Simulated IR/beam sensor across the station opening."""
from __future__ import annotations


class BeamSensor:
    """IR beam across the station opening. `broken=True` while an object
    interrupts the beam."""

    def __init__(self, broken: bool = False) -> None:
        self.broken = broken

    def set(self, broken: bool) -> None:
        self.broken = broken

    def read(self) -> bool:
        return self.broken
