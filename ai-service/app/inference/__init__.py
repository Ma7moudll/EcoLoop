from __future__ import annotations

from functools import lru_cache

from ..config import ai_settings  # noqa: F401
from .base import ClassificationResult, WasteClassifier
from .development import DevelopmentClassifier
from .real import ModelNotReadyError, RealInferenceClassifier


def build_classifier() -> WasteClassifier:
    """Factory. `real` raises [ModelNotReadyError] when no artifact exists so
    the system can never silently claim an untrained model is accurate.

    The default for local dev/test is `development`, which is clearly labelled
    (`model=development` -> backend `source=demo`)."""
    mode = ai_settings.classifier.lower()
    if mode == "real":
        return RealInferenceClassifier()
    if mode == "development":
        return DevelopmentClassifier(
            force_class=ai_settings.development_force_class,
            force_confidence=ai_settings.development_force_confidence,
        )
    raise ValueError(f"Unknown classifier mode {mode!r}")


@lru_cache
def get_classifier() -> WasteClassifier:
    return build_classifier()