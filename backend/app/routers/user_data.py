from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import User
from ..repositories import WasteRepository
from ..security import get_current_user
from ..services import ChallengeService, ImpactService, LeaderboardService

router = APIRouter(tags=["user-data"])


@router.get("/users/me")
def me(
    user: User = Depends(get_current_user), db: Session = Depends(get_db)
) -> dict:
    from .auth import payload_fields

    return {"user": payload_fields(db, user)}


@router.get("/waste/history")
def history(
    user: User = Depends(get_current_user), db: Session = Depends(get_db)
) -> dict:
    from .auth import faculty_name

    events = WasteRepository().list_by_user(db, user.id)
    return {
        "items": [
            {
                "id": e.id,
                "operation_id": e.operation_id,
                "station_id": e.station_id,
                "predicted_class": e.predicted_class,
                "weight_g": round(e.weight_grams, 2),
                "points_awarded": e.points_awarded,
                "created_at": e.created_at.isoformat(),
            }
            for e in events
        ]
    }


@router.get("/waste/history/{event_id}")
def history_event(
    event_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    repo = WasteRepository()
    event = repo.get(db, event_id)
    if event is None or event.user_id != user.id:
        raise HTTPException(status_code=404, detail="Event not found")
    return {
        "item": {
            "id": event.id,
            "operation_id": event.operation_id,
            "station_id": event.station_id,
            "predicted_class": event.predicted_class,
            "weight_g": round(event.weight_grams, 2),
            "points_awarded": event.points_awarded,
            "created_at": event.created_at.isoformat(),
        }
    }


@router.get("/impact")
def impact(
    user: User = Depends(get_current_user), db: Session = Depends(get_db)
) -> dict:
    return ImpactService().for_user(db, user)


@router.get("/leaderboard")
def leaderboard(
    scope: str = "students",
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    return {"entries": LeaderboardService().get_entries(db, scope)}


@router.get("/leaderboard/students")
def leaderboard_students(
    user: User = Depends(get_current_user), db: Session = Depends(get_db)
) -> dict:
    return {"entries": LeaderboardService().get_entries(db, "students")}


@router.get("/leaderboard/faculties")
def leaderboard_faculties(
    user: User = Depends(get_current_user), db: Session = Depends(get_db)
) -> dict:
    return {"entries": LeaderboardService().get_entries(db, "faculties")}


@router.get("/challenges")
def challenges(
    user: User = Depends(get_current_user), db: Session = Depends(get_db)
) -> dict:
    return {"items": ChallengeService().list_for_user(db, user)}