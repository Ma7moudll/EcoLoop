"""Application configuration.

All values come from environment variables (`.env` is supported) so nothing is
hardcoded: database URL, MQTT broker, AI service URL, deposit thresholds and
session lifetime are all configurable (see `.env.example`).
"""
from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # -- API -----------------------------------------------------------------
    app_name: str = "Recycle Vision API"
    api_v1_prefix: str = "/api/v1"
    debug: bool = False

    # -- Security ------------------------------------------------------------
    jwt_secret: str = "dev-only-change-me-in-production"
    jwt_algorithm: str = "HS256"
    jwt_access_token_minutes: int = 60 * 24  # 24h dev sessions

    # -- Database ------------------------------------------------------------
    database_url: str = "postgresql+psycopg2://recycle:recycle@localhost:5432/recycle_vision"

    # -- AI service ----------------------------------------------------------
    ai_service_url: str = "http://localhost:8051"
    ai_timeout_seconds: float = 15.0

    # -- MQTT ----------------------------------------------------------------
    mqtt_broker_host: str = "localhost"
    mqtt_broker_port: int = 1883
    mqtt_username: str | None = None
    mqtt_password: str | None = None
    mqtt_client_id: str = "recycle-backend"
    mqtt_topic_prefix: str = "ecoloop/stations"

    # -- Deposit / routing policy --------------------------------------------
    min_deposit_weight_grams: float = 1.0
    ai_high_confidence: float = 0.80
    ai_medium_confidence: float = 0.50
    deposit_session_ttl_seconds: int = 5 * 60  # 5 minutes, configurable
    automatic_routing_required: bool = False  # HIGH is auto; MEDIUM = manual ok

    # -- Seed data -----------------------------------------------------------
    seed_on_startup: bool = True


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()