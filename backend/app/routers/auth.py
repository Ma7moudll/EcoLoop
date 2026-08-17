from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ..config import settings
from ..database import get_db
from ..models import Faculty, User
from ..repositories import UserRepository
from ..schemas import AuthResponse, LoginRequest, RegisterRequest, UserOut
from ..security import create_access_token, get_current_user, hash_password, verify_password

router = APIRouter(prefix="/auth", tags=["auth"])


def faculty_name(db: Session, faculty_id: str) -> str:
    f = db.get(Faculty, faculty_id)
    return f.name if f else faculty_id


def payload_fields(db: Session, user: User) -> dict:
    return {
        "id": user.id,
        "studentCode": user.student_code,
        "name": user.name,
        "facultyId": user.faculty_id,
        "facultyName": faculty_name(db, user.faculty_id),
        "points": user.points,
    }


def _response(db: Session, user: User) -> AuthResponse:
    token = create_access_token(
        user.id, settings.jwt_secret, settings.jwt_access_token_minutes * 60
    )
    return AuthResponse(token=token, user=payload_fields(db, user))


@router.post("/register", response_model=AuthResponse)
def register(payload: RegisterRequest, db: Session = Depends(get_db)) -> AuthResponse:
    repo = UserRepository()
    email = payload.email.lower().strip()
    if repo.get_by_email(db, email) is not None:
        raise HTTPException(status_code=409, detail="Email already registered")

    code = payload.studentCode or f"S-{email.split('@')[0][:6].upper()}"
    candidate = code
    suffix = 2
    while repo.get_by_student_code(db, candidate) is not None:
        candidate = f"{code}-{suffix}"
        suffix += 1

    faculty = db.get(Faculty, payload.facultyId)
    if faculty is None:
        raise HTTPException(status_code=422, detail="Unknown facultyId")

    user = User(
        email=email,
        student_code=candidate,
        name=payload.name.strip(),
        password_hash=hash_password(payload.password),
        faculty_id=faculty.id,
        points=0,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return _response(db, user)


@router.post("/login", response_model=AuthResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> AuthResponse:
    user = UserRepository().get_by_email(db, payload.email)
    if user is None or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account disabled")
    return _response(db, user)


@router.post("/logout")
def logout(_user: User = Depends(get_current_user)) -> dict:
    # Stateless JWT — the client discards the token. Endpoint exists for the
    # Flutter contract and session-reset clarity.
    return {"status": "logged_out"}


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> UserOut:
    return UserOut(user=payload_fields(db, user))