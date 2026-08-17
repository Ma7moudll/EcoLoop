"""Hardware-simulator configuration (mirrors what the future ESP32 firmware
would hardcode/read from NVS). All values are env-configurable."""
from __future__ import annotations

import os


class SimConfig:
    def __init__(self) -> None:
        self.broker_host: str = os.environ.get("MQTT_BROKER_HOST", "localhost")
        self.broker_port: int = int(os.environ.get("MQTT_BROKER_PORT", "1883"))
        self.mqtt_username: str | None = os.environ.get("MQTT_USERNAME") or None
        self.mqtt_password: str | None = os.environ.get("MQTT_PASSWORD") or None
        self.station_id: str = os.environ.get("STATION_ID", "st-001")
        self.station_code: str = os.environ.get("STATION_CODE", "ST-001")
        self.topic_prefix: str = os.environ.get("MQTT_TOPIC_PREFIX", "ecoloop/stations")

        # Physical behaviour (seconds per unit, noise, thresholds).
        self.movement_time_seconds: float = float(os.environ.get("SIMULATOR_MOVEMENT_TIME", "0.3"))  # per position unit
        self.sensor_noise_grams: float = float(os.environ.get("SIMULATOR_SENSOR_NOISE", "0.2"))
        self.settle_time_seconds: float = float(os.environ.get("SIMULATOR_SETTLE_TIME", "0.8"))
        self.min_weight_grams: float = float(os.environ.get("MIN_DEPOSIT_WEIGHT_GRAMS", "1.0"))
        self.heartbeat_seconds: float = float(os.environ.get("SIMULATOR_HEARTBEAT_SECONDS", "5.0"))
        self.positions: tuple[int, ...] = (1, 2, 3, 4)

    def command_topic(self, station_code: str | None = None) -> str:
        code = station_code or self.station_code
        return f"{self.topic_prefix}/{code}/command"

    def topic(self, suffix: str, station_code: str | None = None) -> str:
        code = station_code or self.station_code
        return f"{self.topic_prefix}/{code}/{suffix}"


sim_config = SimConfig()