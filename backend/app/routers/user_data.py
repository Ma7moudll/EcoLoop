from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import User
from ..repositories import WasteRepository
from ..security import get_current_user
from ..services import ChallengeService, ImpactService, LeaderboardService

router = APIRouter(tags=["user-data"])

# Pagination caps: safe defaults, hard ceilings so a huge limit cannot be
# used to pull the whole table in one request.
_DEFAULT_LIMIT = 20
_MAX_LIMIT = 100


def _page(limit: int, offset: int) -> tuple[int, int]:
    return max(1, min(limit, _MAX_LIMIT)), max(0, offset)


@router.get("/users/me")
def me(
    user: User = Depends(get_current_user), db: Session = Depends(get_db)
) -> dict:
    from .auth import payload_fields

    return {"user": payload_fields(db, user)}


@router.get("/waste/history")
def history(
    limit: int = Query(_DEFAULT_LIMIT, ge=1),
    offset: int = Query(0, ge=0),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    from .auth import faculty_name

    size, skip = _page(limit, offset)
    repo = WasteRepository()
    events, total = repo.list_by_user_paged(db, user.id, size, skip)
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
        ],
        "total": total,
        "limit": size,
        "offset": skip,
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
    limit: int = Query(_DEFAULT_LIMIT, ge=1),
    offset: int = Query(0, ge=0),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    size, skip = _page(limit, offset)
    entries, total = LeaderboardService().get_entries_paged(db, scope, size, skip)
    return {"entries": entries, "total": total, "limit": size, "offset": skip}


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
    limit: int = Query(_DEFAULT_LIMIT, ge=1),
    offset: int = Query(0, ge=0),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    size, skip = _page(limit, offset)
    items, total = ChallengeService().list_for_user_paged(db, user, size, skip)
    return {"items": items, "total": total, "limit": size, "offset": skip}