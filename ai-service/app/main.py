from __future__ import annotations

import time

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from PIL import UnidentifiedImageError

from .inference import get_classifier
from .inference.real import ModelNotReadyError
from .tools.quality_gate import (
    REJECTION_MESSAGES,
    GateState,
    InputQualityGate,
)

app = FastAPI(title="Recycle Vision AI")

# Single stateless gate instance (lazily created on first use).
_gate: InputQualityGate | None = None


def _gate_instance() -> InputQualityGate:
    global _gate
    if _gate is None:
        _gate = InputQualityGate()
    return _gate


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "classifier": _classifier_mode()}


def _reject(state: GateState, detail: str) -> JSONResponse:
    """Structured gate rejection. `CORRUPT_IMAGE` and friends are 422 with a
    machine-readable `code` so callers can distinguish retake flows."""
    return JSONResponse(
        status_code=422,
        content={"code": state.value, "detail": detail},
    )


@app.post("/predict")
def predict(image: UploadFile = File(...)) -> dict:
    data = image.file.read()
    if not data:
        return _reject(GateState.CORRUPT_IMAGE, "Empty image")

    # Camera/input gate runs BEFORE the classifier: blank, blurred, corrupt
    # and empty-background frames never reach predict and can never be routed
    # as high-confidence waste.
    gate_result = _gate_instance().assess(data)
    if gate_result.state is not GateState.VALID_FRAME:
        return _reject(
            gate_result.state, REJECTION_MESSAGES[gate_result.state]
        )

    try:
        classifier = get_classifier()
    except ModelNotReadyError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    try:
        start = time.perf_counter()
        result = classifier.predict(data)
        elapsed_ms = round((time.perf_counter() - start) * 1000, 2)
    except UnidentifiedImageError as exc:
        return _reject(
            GateState.CORRUPT_IMAGE,
            REJECTION_MESSAGES[GateState.CORRUPT_IMAGE],
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"inference failed: {exc}") from exc
    return {**result.to_dict(), "elapsed_ms": elapsed_ms}


def _classifier_mode() -> str:
    from .config import ai_settings

    return ai_settings.classifier