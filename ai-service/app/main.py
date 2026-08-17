from __future__ import annotations

import time

from fastapi import FastAPI, File, HTTPException, UploadFile

from .inference import get_classifier
from .inference.real import ModelNotReadyError

app = FastAPI(title="Recycle Vision AI")


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "classifier": _classifier_mode()}


@app.post("/predict")
def predict(image: UploadFile = File(...)) -> dict:
    data = image.file.read()
    if not data:
        raise HTTPException(status_code=422, detail="Empty image")
    try:
        classifier = get_classifier()
    except ModelNotReadyError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    try:
        start = time.perf_counter()
        result = classifier.predict(data)
        elapsed_ms = round((time.perf_counter() - start) * 1000, 2)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"inference failed: {exc}") from exc
    return {**result.to_dict(), "elapsed_ms": elapsed_ms}


def _classifier_mode() -> str:
    from .config import ai_settings

    return ai_settings.classifier