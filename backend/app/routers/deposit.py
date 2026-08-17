from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import User
from ..mqtt import RuntimePublisher
from ..schemas import CallbackEvent, CreateSessionRequest
from ..security import get_current_user
from ..services import DepositService
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
    """Creates a tracked deposit session and issues the MQTT routing command
    to the station. Awarding points is impossible here — only physical MQTT
    sensor events can complete a deposit."""
    try:
        session = DepositService(_publisher).create_session(
            db, user, prediction_id=payload.ai_prediction_id, station_id=payload.station_id
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return _wire_session(session)


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
def callback(event: CallbackEvent, db: Session = Depends(get_db)) -> dict:
    """HTTP parity path for hardware events (used when a MQTT bridge is not
    available). The normal path is MQTT directly; both invoke the exact same
    validation pipeline and can never award points without a valid physics
    event."""
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
        "prediction_id": session.ai_prediction_id,
        "station_id": session.station_id,
        "predicted_class": session.expected_class,
        "expected_position": session.expected_position,
        "actual_position": session.actual_position or 0,
        "weight_g": round(session.weight_grams or 0.0, 2),
        "mechanical_confirmed": bool(session.mechanical_confirmed),
        "potential_points": session.potential_points,
        "points_awarded": session.potential_points if confirmed else 0,
        "status": session.status,
        "expires_at": _naive_utc(session.expires_at).isoformat(),
        "reject_reason": session.reject_reason,
    }