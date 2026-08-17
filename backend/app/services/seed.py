from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy.orm import Session

from ..models import Faculty, OperationCounter, RoutingPolicy, User
from ..security.password import hash_password

DATE_FMT = "%Y%m%d"  # compact datetime for OP-YYYYMMDD-NNNNNN ids


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _day(date: datetime) -> str:
    return date.strftime(DATE_FMT)


def next_operation_id(db: Session, at: datetime | None = None) -> str:
    """Mints `OP-YYYYMMDD-NNNNNN` inside the current transaction. The counter
    row is locked (PostgreSQL) so concurrent minting cannot collide; SQLite
    tests are serialized so the lock is a no-op but still correct."""
    now = at or utcnow()
    day = _day(now)
    counter = db.query(OperationCounter).filter(OperationCounter.day == day).with_for_update().first()
    if counter is None:
        counter = OperationCounter(day=day, value=0)
        db.add(counter)
    counter.value += 1
    db.flush()
    return f"OP-{day}-{counter.value:06d}"


class SeedError(RuntimeError):
    pass


def seed(db: Session) -> None:
    """Idempotent development seed. Creates faculties, stations, routing
    policy and a well-known dev user (`demo@recycle.vision` / `demo123`)."""
    from ..models import Station

    if db.query(Faculty).first() is not None:
        return

    engineering = Faculty(id="engineering", name="Faculty of Engineering")
    science = Faculty(id="science", name="Faculty of Science")
    commerce = Faculty(id="commerce", name="Faculty of Commerce")
    medicine = Faculty(id="medicine", name="Faculty of Medicine")
    db.add_all([engineering, science, commerce, medicine])
    db.flush()

    db.add_all(
        [
            Station(
                id="st-001",
                station_code="ST-001",
                name="EcoLoop Engineering Station",
                status="offline",
            )
        ]
    )

    routing = [
        ("plastic", 1, 5),
        ("metal", 2, 10),
        ("paper", 3, 5),
        ("other", 4, 0),
    ]
    db.add_all(
        [
            RoutingPolicy(
                id=f"routing-{cls}", waste_class=cls, position=pos, potential_points=pts
            )
            for cls, pos, pts in routing
        ]
    )

    db.add_all(
        [
            User(
                id="u-demo",
                email="demo@recycle.vision",
                student_code="S-DEMO1",
                name="Demo Student",
                password_hash=hash_password("demo123"),
                faculty_id="engineering",
                points=45,
            )
        ]
    )

    db.add_all(
        [
            # A counter row so OP-<today>-000001 starts at 1.
            OperationCounter(day=_day(utcnow()), value=0)
        ]
    )
    db.commit()


def seed_faculty_leaderboard(db: Session) -> None:
    from ..models import LeaderboardEntry

    for faculty in db.query(Faculty).all():
        entry = (
            db.query(LeaderboardEntry)
            .filter(LeaderboardEntry.scope == "faculties", LeaderboardEntry.entity_id == faculty.id)
            .first()
        )
        if entry is None:
            db.add(
                LeaderboardEntry(
                    id=f"lb-f-{faculty.id}",
                    scope="faculties",
                    entity_id=faculty.id,
                    name=faculty.name,
                    detail="Faculty",
                    points=0,
                    faculty_id=faculty.id,
                )
            )
    db.commit()