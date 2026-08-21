from __future__ import annotations

import logging
from collections import defaultdict

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models import Challenge, User, UserChallenge, WasteEvent

logger = logging.getLogger("recycle.challenges")


class ChallengeService:
    def list_for_user(self, db: Session, user: User) -> list[dict]:
        progress = self._progress(db, user)
        completed_ids = self._completed_ids(db, user)
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
                "completed": c.id in completed_ids or progress[c.waste_class] >= c.target_kg,
                "active": bool(c.active),
            }
            for c in rows
        ]

    def list_for_user_paged(
        self, db: Session, user: User, limit: int, offset: int
    ) -> tuple[list[dict], int]:
        items = self.list_for_user(db, user)
        return items[offset : offset + limit], len(items)

    def on_deposit_confirmed(self, db: Session, user: User, waste_class: str) -> int:
        """Called from the validated deposit path AFTER base points are awarded.

        Completes every active challenge for this waste class whose target the
        user's confirmed tonnage has now reached. Completion and reward are
        persisted atomically; the unique (user_id, challenge_id) constraint
        makes a duplicate reward impossible even under concurrent events.

        Returns the total bonus points awarded by THIS call (0 when nothing
        newly completed)."""
        progress = self._progress(db, user)
        already = self._completed_ids(db, user)
        bonus = 0
        challenges = db.execute(
            select(Challenge).where(
                Challenge.waste_class == waste_class,
                Challenge.active.is_(True),
            )
        ).scalars()
        for challenge in challenges:
            if challenge.id in already:
                continue
            if progress[waste_class] < challenge.target_kg:
                continue
            if challenge.reward_points <= 0:
                # Nothing to award; still persist completion for the UI.
                db.add(
                    UserChallenge(
                        id=UserChallenge.new_id(),
                        user_id=user.id,
                        challenge_id=challenge.id,
                        reward_points=0,
                    )
                )
                logger.info(
                    "[CHALLENGE] completed (no reward) challenge=%s user=%s",
                    challenge.id, user.id,
                )
                continue
            db.add(
                UserChallenge(
                    id=UserChallenge.new_id(),
                    user_id=user.id,
                    challenge_id=challenge.id,
                    reward_points=challenge.reward_points,
                )
            )
            user.points += challenge.reward_points
            bonus += challenge.reward_points
            logger.info(
                "[CHALLENGE] completed challenge=%s user=%s reward=%s",
                challenge.id, user.id, challenge.reward_points,
            )
        return bonus

    def _completed_ids(self, db: Session, user: User) -> set[str]:
        rows = db.execute(
            select(UserChallenge.challenge_id).where(UserChallenge.user_id == user.id)
        ).scalars()
        return set(rows)

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
