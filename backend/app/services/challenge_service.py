from __future__ import annotations

from collections import defaultdict

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models import Challenge, User, WasteEvent


class ChallengeService:
    def list_for_user(self, db: Session, user: User) -> list[dict]:
        progress = self._progress(db, user)
        rows = list(db.execute(select(Challenge)).scalars())
        return [
            {
                "id": c.id,
                "title": c.title,
                "description": c.description,
                "theme_emoji": c.theme_emoji,
                "target_kg": c.target_kg,
                "current_kg": round(progress[c.waste_class], 3),
                "reward_points": c.reward_points,
                "completed": bool(c.completed) or progress[c.waste_class] >= c.target_kg,
                "active": bool(c.active),
            }
            for c in rows
        ]

    def _progress(self, db: Session, user: User) -> dict[str, float]:
        kg: dict[str, float] = defaultdict(float)
        events = db.execute(
            select(WasteEvent).where(
                WasteEvent.user_id == user.id,
                WasteEvent.status == "confirmed",
            )
        ).scalars()
        for e in events:
            kg[e.predicted_class] += e.weight_grams / 1000.0
        return kg