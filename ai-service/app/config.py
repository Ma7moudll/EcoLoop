"""AI service configuration."""
from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class AISettings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "Recycle Vision AI"
    # classifier = real | development
    classifier: str = "development"
    # Real classifier: path to the trained model artifact (onnx/tflite/torch).
    model_path: str = ""

    # Development classifier overrides (test/scenario reproducibility only).
    development_force_class: str = ""
    development_force_confidence: float = 0.0

    classes: tuple[str, ...] = ("plastic", "metal", "paper", "other")

    host: str = "0.0.0.0"
    port: int = 8051


@lru_cache
def get_ai_settings() -> AISettings:
    return AISettings()


ai_settings = get_ai_settings()