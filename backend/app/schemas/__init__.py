from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field

WasteClass = Any  # 'plastic' | 'metal' | 'paper' | 'other'


class RegisterRequest(BaseModel):
    name: str = Field(min_length=1, max_length=128)
    email: str
    studentCode: str | None = Field(default=None, max_length=64)
    facultyId: str = Field(default="engineering")
    password: str = Field(min_length=6, max_length=128)


class LoginRequest(BaseModel):
    email: str
    password: str


class AuthResponse(BaseModel):
    token: str
    user: dict[str, Any]


class UserOut(BaseModel):
    user: dict[str, Any]


class PredictionResponse(BaseModel):
    prediction_id: str
    operation_id: str
    predicted_class: str
    confidence: float
    confidence_level: str
    recyclable: bool
    destination_position: int
    potential_points: int
    expires_at: datetime
    source: str


class CreateSessionRequest(BaseModel):
    ai_prediction_id: str
    station_id: str = "st-001"


class CancelRequest(BaseModel):
    operation_id: str


class DepositCreatedResponse(BaseModel):
    deposit: dict[str, Any]


class DepositConfirmRequest(BaseModel):
    """Accepted for API continuity ONLY when running the legacy simulator
    bridge. Real deposits are completed exclusively via MQTT sensor events."""

    operation_id: str
    actual_position: int
    weight_g: float
    mechanical_confirmed: bool = True


class CallbackEvent(BaseModel):
    """Terminal physical deposit event — the MQTT `deposit_result` payload.
    Used by the HTTP callback parity path and by MQTT message decoding."""

    station_id: str
    operation_id: str
    event: str = "deposit_result"
    status: str = "confirmed"
    actual_position: int = 0
    carriage_position: int = 0
    weight_grams: float = 0.0
    weight_stable: bool = False
    beam_event_seen: bool = False
    mechanical_confirmed: bool = False
    reason: str | None = None