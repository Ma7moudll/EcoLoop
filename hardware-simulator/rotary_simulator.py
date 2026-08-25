"""Rotary Sorting Mechanism V2 simulator — drop-in for the future ESP32
rotary firmware.

Speaks the EXACT Recycle Vision station MQTT contract
(`docs/mqtt-contract.md`), but reports the mechanism-neutral
`mechanism_position` field (never `carriage_position`) and identifies itself
with `mechanism = "rotary"` in heartbeats/status.

Flow per deposit (identical lifecycle to V1):

    route command -> ROUTING -> MOVING (chute rotates, telemetry)
      -> POSITIONED -> READY_FOR_DEPOSIT -> DETECTING (beam)
      -> MEASURING (weight ramp) -> DEPOSIT_CONFIRMED
      -> terminal deposit_result -> RESETTING -> IDLE

The machine reports physics only; the backend decides validity and points.
"""
from __future__ import annotations

import logging
import os
import time
from collections import deque
from datetime import datetime, timezone

from camera import CaptureUploader
from config import SimConfig
from hardware import (
    BeamSensor,
    LoadCell,
    MachineState,
    RotaryChute,
    RotaryFillLevel,
    RotaryJamError,
    RotaryStation,
    settle_profile,
)
from mqtt_client import SimulatorMqttClient
from scenarios import DepositPlan, get_scenario

logger = logging.getLogger("sim.rotary")

_RAMP_STEP = float(os.environ.get("SIMULATOR_RAMP_STEP", "0.05"))


def _sleep(seconds: float) -> None:
    if seconds > 0:
        time.sleep(seconds)


class EcoLoopRotarySimulator:
    """Station V2 runtime: rotary chute instead of carriage, identical MQTT
    behaviour otherwise."""

    def __init__(
        self,
        config: SimConfig | None = None,
        mqtt: SimulatorMqttClient | None = None,
        chute: RotaryChute | None = None,
        load_cell: LoadCell | None = None,
        station: RotaryStation | None = None,
        capture_uploader: CaptureUploader | None = None,
        skip_homing: bool = False,
    ) -> None:
        self.cfg = config or SimConfig()
        self.mqtt = mqtt or SimulatorMqttClient(
            self.cfg.broker_host,
            self.cfg.broker_port,
            client_id=f"sim-rotary-{self.cfg.station_code.lower()}",
            username=self.cfg.mqtt_username,
            password=self.cfg.mqtt_password,
            tls=self.cfg.mqtt_tls,
        )
        load_cell = load_cell or LoadCell(noise_grams=self.cfg.sensor_noise_grams)
        beam = BeamSensor()
        chute = chute or RotaryChute()
        fill = {
            name: RotaryFillLevel(distance_mm=250.0 - 30 * i)
            for i, name in enumerate(("PLASTIC", "METAL", "PAPER", "OTHER"))
        }
        self.station = station or RotaryStation(
            chute=chute, load_cell=load_cell, beam=beam, fill_levels=fill
        )
        self.capture = capture_uploader or CaptureUploader(self.cfg)
        self._running = False
        # §21 idempotency: MQTT is at-least-once, so the STATION owns
        # duplicate suppression. An operation may execute exactly once —
        # never while running, never again after completion.
        self._in_flight: set[str] = set()
        self._completed: deque[str] = deque(maxlen=64)
        if not skip_homing:
            self.home()

    # -- lifecycle -------------------------------------------------------------

    def home(self) -> None:
        """Firmware homing sequence on boot / after recovery."""
        try:
            for _ in self.station.chute.home():
                pass
        except TimeoutError as exc:
            logger.error("[HOMING] FAILED: %s", exc)
            raise
        logger.info("[HOMING] chute at home reference (0°, PLASTIC)")

    def start(self, hold: bool = True) -> None:
        self.mqtt.set_command_handler(self._on_command)
        self.mqtt.start(self.cfg.command_topic())
        logger.info("Station: %s (mechanism=rotary)", self.cfg.station_code)
        logger.info("[MQTT] waiting for commands on %s", self.cfg.command_topic())
        self._running = True
        while self._running and hold:
            self._heartbeat()
            _sleep(self.cfg.heartbeat_seconds)

    def stop(self) -> None:
        self._running = False
        self.mqtt.stop()

    # -- MQTT handler -----------------------------------------------------------

    def _on_command(self, command: dict) -> None:
        kind = command.get("command")
        operation_id = command.get("operation_id")
        if kind not in ("route", "capture_request"):
            logger.info("[CMD] ignoring %r", command.get("command"))
            return
        if kind == "capture_request":
            logger.info("[CMD] capture_request operation=%s", operation_id)
            try:
                self.capture.upload(operation_id)
            except Exception:
                logger.exception("[SIM] capture upload failed for %s", operation_id)
            return
        # §21: suppress in-flight AND completed operations (QoS-1 redelivery).
        if operation_id in self._in_flight or operation_id in self._completed:
            logger.warning("[CMD] duplicate route for %s ignored", operation_id)
            return
        destination = int(command.get("destination_position") or 0)
        self._in_flight.add(operation_id)
        logger.info("[CMD] route operation=%s destination=%s", operation_id, destination)
        try:
            self.run_plan(operation_id, destination, DepositPlan())
        except Exception:
            logger.exception("[SIM] plan execution failed for %s", operation_id)
        finally:
            self._in_flight.discard(operation_id)
            self._completed.append(operation_id)

    # -- plan execution ----------------------------------------------------------

    def run_plan(self, operation_id: str, destination: int | None, plan: DepositPlan) -> dict:
        machine = self.station.machine
        effective = plan.destination_position if plan.destination_position is not None else destination
        self.station.chute.jam_at_angle = plan.jam_angle

        machine.transition(MachineState.ROUTING)
        self._emit(operation_id, "state_changed", state="ROUTING",
                   destination_position=effective)

        machine.transition(MachineState.MOVING)
        self._emit(operation_id, "state_changed", state="MOVING")

        target = effective if plan.actual_position is None else plan.actual_position
        try:
            for angle in self.station.chute.route_to_position(target):
                self._sensor(operation_id, mechanism_position=self.station.chute.mechanism_position(),
                             current_position=self.station.chute.mechanism_position(),
                             angle_deg=round(angle, 2))
        except RotaryJamError as exc:
            return self._jammed(operation_id, str(exc))
        except TimeoutError as exc:
            return self._timed_out(operation_id, str(exc))

        machine.transition(MachineState.POSITIONED)
        self._emit(operation_id, "state_changed", state="POSITIONED",
                   mechanism_position=self.station.chute.mechanism_position())

        if plan.actual_position is not None and plan.actual_position != effective:
            machine.transition(MachineState.WRONG_POSITION)
            self._emit(operation_id, "state_changed", state="WRONG_POSITION",
                       actual_position=target)
            self._sensor(operation_id, weight_grams=plan.final_weight or 18.4)
            terminal = self._terminal(operation_id, actual_position=target,
                                      weight=plan.final_weight or 18.4,
                                      status=plan.emit_machine_status,
                                      mechanical=plan.mechanical_confirmed)
            self._reset(operation_id)
            return terminal

        machine.transition(MachineState.READY_FOR_DEPOSIT)
        self._emit(operation_id, "state_changed", state="READY_FOR_DEPOSIT")

        machine.transition(MachineState.DETECTING)
        if plan.beam_seen:
            self.station.beam.set(True)
        self._sensor(operation_id, beam_broken=self.station.beam.broken, weight_grams=0.0)
        self._emit(operation_id, "state_changed", state="DETECTING")

        machine.transition(MachineState.MEASURING)
        self._emit(operation_id, "state_changed", state="MEASURING")
        final_weight = self._run_weight_ramp(operation_id, plan)
        self.station.beam.set(False)
        self._sensor(operation_id, beam_broken=False, weight_stable=True,
                     weight_grams=final_weight)

        if plan.emit_machine_status != "confirmed":
            machine.transition(
                MachineState.UNDERWEIGHT if plan.emit_machine_status == "underweight"
                else MachineState.SENSOR_ERROR
            )
            self._emit(operation_id, "state_changed", state=machine.state.value,
                       weight_grams=final_weight)
            terminal = self._terminal(operation_id,
                                      actual_position=self.station.chute.mechanism_position(),
                                      weight=final_weight, status=plan.emit_machine_status,
                                      mechanical=False)
            self._reset(operation_id)
            return terminal

        machine.transition(MachineState.DEPOSIT_CONFIRMED)
        self._emit(operation_id, "state_changed", state="DEPOSIT_CONFIRMED")

        if plan.delay_before_terminal > 0 and _RAMP_STEP > 0:
            _sleep(plan.delay_before_terminal)

        terminal = self._terminal(operation_id,
                                  actual_position=self.station.chute.mechanism_position(),
                                  weight=final_weight, status=plan.emit_machine_status,
                                  mechanical=plan.mechanical_confirmed)
        self._reset(operation_id)

        if plan.duplicate_terminal:
            self._publish_terminal(operation_id, terminal)
        return terminal

    # -- helpers -------------------------------------------------------------------

    def _jammed(self, operation_id: str, reason: str) -> dict:
        # Transition the machine FIRST (MOVING -> JAMMED is the contract path)
        # so RESETTING/IDLE and post-fault re-homing can proceed.
        if self.station.machine.can_transition(MachineState.JAMMED):
            self.station.machine.transition(MachineState.JAMMED)
        self._emit(operation_id, "state_changed", state="JAMMED", reason=reason)
        terminal = self._terminal(operation_id,
                                  actual_position=self.station.chute.mechanism_position(),
                                  weight=0.0, status="jam", mechanical=False,
                                  beam_seen=False)
        self._reset(operation_id)
        return terminal

    def _timed_out(self, operation_id: str, reason: str) -> dict:
        self.station.machine.transition(MachineState.TIMEOUT)
        self._emit(operation_id, "state_changed", state="TIMEOUT", reason=reason)
        terminal = self._terminal(operation_id,
                                  actual_position=self.station.chute.mechanism_position(),
                                  weight=0.0, status="timeout", mechanical=False,
                                  beam_seen=False)
        self._reset(operation_id)
        return terminal

    def _reset(self, operation_id: str) -> None:
        machine = self.station.machine
        errored = machine.in_error()
        if machine.can_transition(MachineState.RESETTING):
            machine.transition(MachineState.RESETTING)
            self._emit(operation_id, "state_changed", state="RESETTING")
        if errored:
            # Firmware behaviour after a fault: re-home before accepting work.
            try:
                list(self.station.chute.home())
            except TimeoutError:
                pass
        if machine.can_transition(MachineState.IDLE):
            machine.transition(MachineState.IDLE)
            self._emit(operation_id, "state_changed", state="IDLE")

    def _run_weight_ramp(self, operation_id: str, plan: DepositPlan) -> float:
        ramp = settle_profile(plan.weight_timeline)
        last_t = plan.weight_timeline[-1][0]
        final_value = plan.final_weight if plan.final_weight is not None else ramp(last_t)
        if _RAMP_STEP <= 0:
            self.station.load_cell.set_value(final_value)
            reading = self.station.load_cell.read_weight()
            self._sensor(operation_id, weight_grams=reading, weight_stable=True,
                         beam_broken=True,
                         mechanism_position=self.station.chute.mechanism_position())
            return round(reading, 2)
        t = 0.0
        while t <= last_t + 1e-9:
            self.station.load_cell.set_value(ramp(t))
            reading = self.station.load_cell.read_weight()
            self._sensor(operation_id, weight_grams=reading,
                         weight_stable=(t >= last_t), beam_broken=True,
                         mechanism_position=self.station.chute.mechanism_position())
            _sleep(_RAMP_STEP)
            t += _RAMP_STEP
        self.station.load_cell.set_value(final_value)
        return round(self.station.load_cell.read_weight(), 2)

    def _terminal(self, operation_id: str, actual_position: int, weight: float,
                  status: str, mechanical: bool, beam_seen: bool = True) -> dict:
        terminal = {
            "station_id": self.cfg.station_code,
            "operation_id": operation_id,
            "event": "deposit_result",
            "status": status,
            "actual_position": actual_position,
            # V2 reports ONLY the neutral field — never carriage_position.
            "mechanism_position": self.station.chute.mechanism_position(),
            "weight_grams": round(weight, 2),
            "weight_stable": weight >= self.cfg.min_weight_grams,
            "beam_event_seen": beam_seen,
            "mechanical_confirmed": mechanical,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        self._publish_terminal(operation_id, terminal)
        return terminal

    def _publish_terminal(self, operation_id: str, terminal: dict) -> None:
        self.mqtt.publish(self.cfg.topic("event"), terminal)
        logger.info("[TERMINAL] operation=%s status=%s", operation_id, terminal["status"])

    def _emit(self, operation_id: str, event: str, state: str, **extra) -> None:
        payload = {
            "station_id": self.cfg.station_code,
            "operation_id": operation_id,
            "event": event,
            "state": state,
            **extra,
        }
        self.mqtt.publish(self.cfg.topic("event"), payload)

    def _sensor(self, operation_id: str, **fields) -> None:
        payload = {
            "station_id": self.cfg.station_code,
            "operation_id": operation_id,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            **fields,
        }
        self.mqtt.publish(self.cfg.topic("sensor"), payload)

    def _heartbeat(self) -> None:
        payload = {
            "station_id": self.cfg.station_code,
            "status": "online",
            "mechanism": "rotary",
            "state": self.station.state.value,
            "mechanism_position": self.station.chute.mechanism_position(),
            "uptime_s": 0,
        }
        self.mqtt.publish(self.cfg.topic("heartbeat"), payload)
        logger.info("Heartbeat: OK")


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(
        description="EcoLoop Rotary V2 simulator — same MQTT contract as the "
        "carriage V1 simulator, reporting mechanism_position."
    )
    parser.add_argument("--broker", default=None)
    parser.add_argument("--port", type=int, default=None)
    parser.add_argument("--scenario", default=None,
                        help="Run one scenario once then exit.")
    args = parser.parse_args()

    cfg = SimConfig()
    if args.broker:
        cfg.broker_host = args.broker
    if args.port:
        cfg.port = args.port

    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s [%(name)s] %(levelname)s %(message)s")
    sim = EcoLoopRotarySimulator(config=cfg)
    if args.scenario:
        plan = get_scenario(args.scenario)
        sim.mqtt.set_command_handler(lambda cmd: None)
        sim.mqtt.start(cfg.command_topic())
        sim.run_plan("OP-DEMO-000001", plan.destination_position or 1, plan)
        sim.stop()
        return
    sim.start(hold=True)


if __name__ == "__main__":
    main()
