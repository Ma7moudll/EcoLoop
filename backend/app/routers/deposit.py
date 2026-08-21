from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from ..config import settings
from ..database import get_db
from ..models import User
from ..mqtt import RuntimePublisher
from ..schemas import CallbackEvent, CreateSessionRequest
from ..security import get_current_user
from ..services import DepositService
from ..services.ai_client import AiGateRejection, AiWireError
from ..services.deposit_service import DepositEventError, DuplicateDepositError

logger = logging.getLogger("recycle.deposit")

router = APIRouter(prefix="/deposit", tags=["deposit"])

_publisher = RuntimePublisher()


@router.post("/session")
def create_session(
    payload: CreateSessionRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """Creates a tracked deposit session.

    With `ai_prediction_id` (legacy phone-camera path) the MQTT routing command
    is issued immediately. Without one (FINAL station-camera path) the session
    is created capture-first and a `capture_request` command tells the station
    camera to snap the frame; `POST /deposit/capture` then classifies and
    routes. Awarding points is impossible here — only physical MQTT sensor
    events can complete a deposit."""
    try:
        session = DepositService(_publisher).create_session(
            db,
            user,
            prediction_id=payload.ai_prediction_id,
            station_id=payload.station_id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return _wire_session(session)


@router.post("/capture")
def capture(
    image: UploadFile = File(...),
    operation_id: str = Form(...),
    station_code: str = Form(...),
    x_station_key: str = Header(default="", alias="X-Station-Key"),
    db: Session = Depends(get_db),
) -> dict:
    """Station-camera capture endpoint (FINAL architecture).

    The STATION camera — not the phone — is the classification source. The
    backend runs the real `PredictService`, attaches the prediction to the
    session and auto-routes per the confidence policy (HIGH auto / MEDIUM
    manual / LOW rejected). A rejected frame from the AI input gate returns a
    structured 422 so the camera can retake. Points still require the physical
    MQTT `deposit_result` event — this endpoint can never award points."""
    if not x_station_key or x_station_key != settings.station_api_key:
        return JSONResponse(status_code=401, content={"error": "Invalid station key"})

    # Reject oversized uploads BEFORE reading/expensive processing. Prefer the
    # declared Content-Length when present, then enforce the hard cap while
    # streaming so a lying header cannot bypass the limit.
    declared = image.size
    if declared is not None and declared > settings.max_upload_bytes:
        return JSONResponse(status_code=413, content={"error": "payload_too_large"})
    image_bytes = image.file.read(settings.max_upload_bytes + 1)
    if len(image_bytes) > settings.max_upload_bytes:
        return JSONResponse(status_code=413, content={"error": "payload_too_large"})
    if not image_bytes:
        raise HTTPException(status_code=422, detail="Empty capture")
    try:
        return DepositService(_publisher).handle_capture(
            db, operation_id, station_code, image_bytes,
            image_url=f"station-camera://{station_code}",
        )
    except AiGateRejection as exc:
        return JSONResponse(status_code=422, content={"code": exc.code, "error": exc.detail})
    except AiWireError as exc:
        # AI service unreachable/errored: the session was reverted to `capture`
        # so the camera can retake; surface a structured 503 (not a 500 leak).
        return JSONResponse(status_code=503, content={"code": "AI_UNAVAILABLE", "error": str(exc)})
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.get("/{operation_id}")
def get_deposit(
    operation_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    from ..repositories import DepositRepository

    session = DepositRepository().get_by_operation_id(db, operation_id)
    if session is None or session.user_id != user.id:
        raise HTTPException(status_code=404, detail="Deposit not found")
    return _wire_session(session)


@router.post("/{operation_id}/cancel")
def cancel(
    operation_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    try:
        session = DepositService(_publisher).cancel(db, user, operation_id)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return _wire_session(session)


@router.post("/callback/event")
def callback(
    event: CallbackEvent,
    x_station_key: str = Header(default="", alias="X-Station-Key"),
    db: Session = Depends(get_db),
) -> dict:
    """HTTP parity path for hardware events (used when a MQTT bridge is not
    available). The normal path is MQTT directly (broker-internal trust
    boundary); this HTTP path is internet-reachable and REQUIRES the same
    `X-Station-Key` as the capture endpoint so a random caller cannot fabricate
    a `deposit_result` event and award themselves points. Both invoke the exact
    same validation pipeline and can never award points without a valid
    physics event."""
    if not x_station_key or x_station_key != settings.station_api_key:
        return JSONResponse(status_code=401, content={"error": "Invalid station key"})
    try:
        result = DepositService(_publisher).complete_from_event(db, event.model_dump())
    except DuplicateDepositError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except DepositEventError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return result


def _wire_session(session) -> dict:
    from ..services.deposit_service import _naive_utc

    confirmed = session.status == "confirmed"
    return {
        "operation_id": session.operation_id,
        "prediction_id": session.ai_prediction_id or "",
        "station_id": session.station_id,
        "predicted_class": session.expected_class or "",
        "expected_position": session.expected_position or 0,
        "confidence": session.confidence or 0.0,
        "confidence_level": session.confidence_level or "",
        "actual_position": session.actual_position or 0,
        "weight_g": round(session.weight_grams or 0.0, 2),
        "mechanical_confirmed": bool(session.mechanical_confirmed),
        "potential_points": session.potential_points,
        "points_awarded": session.potential_points if confirmed else 0,
        "status": session.status,
        "expires_at": _naive_utc(session.expires_at).isoformat(),
        "reject_reason": session.reject_reason,
    }