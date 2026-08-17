from __future__ import annotations

import httpx

from ..config import settings


class AiWireError(RuntimeError):
    """The AI service could not be reached or returned an unexpected shape."""


class AiExternalPrediction:
    __slots__ = ("predicted_class", "confidence", "model")

    def __init__(self, predicted_class: str, confidence: float, model: str) -> None:
        self.predicted_class = predicted_class
        self.confidence = confidence
        self.model = model


class AiServiceClient:
    """HTTP client for the standalone AI service (`POST /predict`).

    The backend only depends on the wire contract; swapping the model provider
    never touches this code.
    """

    def __init__(self, base_url: str | None = None, timeout: float | None = None) -> None:
        self.base_url = (base_url or settings.ai_service_url).rstrip("/")
        self.timeout = timeout if timeout is not None else settings.ai_timeout_seconds

    def predict(self, image_bytes: bytes, content_type: str = "image/jpeg") -> AiExternalPrediction:
        try:
            response = httpx.post(
                f"{self.base_url}/predict",
                files={"image": ("capture.jpg", image_bytes, content_type)},
                timeout=self.timeout,
            )
        except httpx.HTTPError as exc:
            raise AiWireError(f"AI service unreachable: {exc}") from exc
        if response.status_code != 200:
            raise AiWireError(f"AI service error {response.status_code}: {response.text[:200]}")
        data = response.json()
        try:
            return AiExternalPrediction(
                predicted_class=data["predicted_class"],
                confidence=float(data["confidence"]),
                model=str(data.get("model", "ai")),
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise AiWireError(f"Malformed AI response: {data}") from exc