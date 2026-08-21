"""Admin management endpoints — every route requires `role == "admin"`.

Foundation only (no panel): station lifecycle, user moderation, challenge
management. Unrestricted exposure is exactly what this router prevents.
"""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import Challenge, Station, User
from ..security import require_admin

router = APIRouter(prefix="/admin", tags=["admin"], dependencies=[Depends(require_admin)])


# -- stations ------------------------------------------------------------------


class StationUpsert(BaseModel):
    station_code: str
    name: str
    enabled: bool = True


class StationPatch(BaseModel):
    name: str | None = None
    enabled: bool | None = None


@router.post("/stations")
def create_station(payload: StationUpsert, db: Session = Depends(get_db)) -> dict:
    existing = (
        db.execute(select(Station).where(Station.station_code == payload.station_code))
        .scalars()
        .first()
    )
    if existing is not None:
        raise HTTPException(status_code=409, detail="Station code already exists")
    station = Station(
        id=f"st-{uuid.uuid4().hex[:8]}",
        station_code=payload.station_code,
        name=payload.name,
        status="online" if payload.enabled else "disabled",
    )
    db.add(station)
    db.commit()
    db.refresh(station)
    return {"id": station.id, "station_code": station.station_code, "status": station.status}


@router.patch("/stations/{station_id}")
def patch_station(
    station_id: str, payload: StationPatch, db: Session = Depends(get_db)
) -> dict:
    station = db.get(Station, station_id)
    if station is None:
        raise HTTPException(status_code=404, detail="Station not found")
    if payload.name is not None:
        station.name = payload.name
    if payload.enabled is not None:
        station.status = "online" if payload.enabled else "disabled"
    db.commit()
    return {
        "id": station.id,
        "station_code": station.station_code,
        "name": station.name,
        "status": station.status,
    }


# -- users -------------------------------------------------------------------


class UserPatch(BaseModel):
    is_active: bool | None = None


@router.get("/users")
def list_users(db: Session = Depends(get_db)) -> dict:
    users = db.execute(select(User).order_by(User.email)).scalars().all()
    return {
        "items": [
            {
                "id": u.id,
                "email": u.email,
                "name": u.name,
                "role": u.role,
                "is_active": u.is_active,
                "points": u.points,
            }
            for u in users
        ]
    }


@router.patch("/users/{user_id}")
def patch_user(
    user_id: str,
    payload: UserPatch,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict:
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    if payload.is_active is not None:
        if not payload.is_active and user.id == admin.id:
            raise HTTPException(status_code=422, detail="Cannot deactivate your own account")
        user.is_active = payload.is_active
    db.commit()
    return {"id": user.id, "is_active": user.is_active}


# -- challenges -----------------------------------------------------------------


class ChallengeCreate(BaseModel):
    id: str | None = None  # server-generated when absent
    title: str
    description: str
    theme_emoji: str = "♻️"
    waste_class: str
    target_kg: float
    reward_points: int = 0


class ChallengePatch(BaseModel):
    active: bool | None = None


@router.post("/challenges")
def create_challenge(payload: ChallengeCreate, db: Session = Depends(get_db)) -> dict:
    challenge_id = payload.id or f"ch-{uuid.uuid4().hex[:12]}"
    if db.get(Challenge, challenge_id) is not None:
        raise HTTPException(status_code=409, detail="Challenge id already exists")
    challenge = Challenge(
        id=challenge_id,
        title=payload.title,
        description=payload.description,
        theme_emoji=payload.theme_emoji,
        waste_class=payload.waste_class,
        target_kg=payload.target_kg,
        reward_points=payload.reward_points,
    )
    db.add(challenge)
    db.commit()
    return {"id": challenge.id, "title": challenge.title}


@router.patch("/challenges/{challenge_id}")
def patch_challenge(
    challenge_id: str, payload: ChallengePatch, db: Session = Depends(get_db)
) -> dict:
    challenge = db.get(Challenge, challenge_id)
    if challenge is None:
        raise HTTPException(status_code=404, detail="Challenge not found")
    if payload.active is not None:
        challenge.active = payload.active
    db.commit()
    return {"id": challenge.id, "active": challenge.active}
