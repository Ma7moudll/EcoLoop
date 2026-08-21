from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from ..config import settings
from ..database import get_db
from ..models import AuthToken, Faculty, User
from ..models.auth_token import hash_token
from ..repositories import UserRepository
from ..schemas import AuthResponse, LoginRequest, RegisterRequest, UserOut
from ..security import create_access_token, get_current_user, hash_password, verify_password
from ..security.jwt import decode_access_token
from ..security.rate_limit import MemoryRateLimiter, client_identity
from ..security.revocation import revocations
from ..services.mailer import get_mailer

router = APIRouter(prefix="/auth", tags=["auth"])

# Sliding-window limiters (per process). Login is deliberately tight —
# brute force gets 5 attempts/minute/IP; register allows a lab room.
_login_limiter = MemoryRateLimiter(
    settings.auth_login_rate_limit, settings.auth_rate_window_seconds
)
_register_limiter = MemoryRateLimiter(
    settings.auth_register_rate_limit, settings.auth_rate_window_seconds
)


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


def _issue_token(
    db: Session,
    user: User,
    purpose: str,
    ttl_seconds: int,
) -> str:
    """Creates a one-time token; only its hash is persisted."""
    raw = uuid.uuid4().hex + uuid.uuid4().hex
    db.add(
        AuthToken(
            id=AuthToken.new_id(),
            user_id=user.id,
            purpose=purpose,
            token_hash=hash_token(raw),
            expires_at=datetime.now(timezone.utc) + timedelta(seconds=ttl_seconds),
        )
    )
    db.commit()
    return raw


def _consume_token(db: Session, raw_token: str, purpose: str) -> AuthToken | None:
    """Single-use validation: hash lookup + purpose + expiry + not used."""
    record = (
        db.query(AuthToken)
        .filter(
            AuthToken.token_hash == hash_token(raw_token),
            AuthToken.purpose == purpose,
            AuthToken.used_at.is_(None),
        )
        .first()
    )
    if record is None:
        return None
    expires = record.expires_at
    if expires.tzinfo is None:
        expires = expires.replace(tzinfo=timezone.utc)
    if expires < datetime.now(timezone.utc):
        return None
    record.used_at = datetime.now(timezone.utc)
    db.commit()
    return record


@router.post("/register", response_model=AuthResponse)
def register(payload: RegisterRequest, request: Request, db: Session = Depends(get_db)) -> AuthResponse:
    if not _register_limiter.hit(client_identity(request)):
        raise HTTPException(status_code=429, detail="Too many requests. Try again later.")
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

    # Email verification: one-time token delivered via the configured mailer
    # (console in development). Delivery is a deployment concern.
    verification = _issue_token(
        db, user, "email_verification", settings.email_verification_token_ttl_seconds
    )
    get_mailer().send(
        to=email,
        subject="Verify your EcoLoop account",
        body=(
            f"Welcome to EcoLoop, {user.name}!\n\n"
            f"Verify your account: {settings.public_base_url}/verify-email?token={verification}\n"
            f"This link expires in {settings.email_verification_token_ttl_seconds // 3600} hours."
        ),
    )

    return _response(db, user)


@router.post("/login", response_model=AuthResponse)
def login(payload: LoginRequest, request: Request, db: Session = Depends(get_db)) -> AuthResponse:
    if not _login_limiter.hit(client_identity(request)):
        raise HTTPException(status_code=429, detail="Too many login attempts. Try again later.")
    user = UserRepository().get_by_email(db, payload.email)
    if user is None or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account disabled")
    return _response(db, user)


@router.post("/logout")
def logout(
    request: Request,
    user: User = Depends(get_current_user),
) -> dict:
    """Revokes the presented token's jti for its remaining lifetime."""
    auth_header = request.headers.get("authorization", "")
    token = auth_header.removeprefix("Bearer ").strip()
    try:
        claims = decode_access_token(token, settings.jwt_secret)
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid or expired token") from exc
    remaining = float(claims.get("exp", 0)) - datetime.now(timezone.utc).timestamp()
    revocations.revoke(str(claims.get("jti", "")), max(remaining, 0.0))
    return {"status": "logged_out"}


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> UserOut:
    return UserOut(user=payload_fields(db, user))


@router.post("/forgot-password")
def forgot_password(payload: dict, db: Session = Depends(get_db)) -> dict:
    """Always responds generically — no user enumeration.

    A real user receives a one-time reset link via the configured mailer;
    an unknown email silently does nothing."""
    email = str(payload.get("email", "")).lower().strip()
    user = UserRepository().get_by_email(db, email) if email else None
    if user is not None and user.is_active:
        raw = _issue_token(
            db, user, "password_reset", settings.password_reset_token_ttl_seconds
        )
        get_mailer().send(
            to=email,
            subject="Reset your EcoLoop password",
            body=(
                f"Reset your password: {settings.public_base_url}/reset-password?token={raw}\n"
                f"This link expires in {settings.password_reset_token_ttl_seconds // 60} minutes "
                "and can be used once."
            ),
        )
    return {"status": "sent"}


@router.post("/reset-password")
def reset_password(payload: dict, db: Session = Depends(get_db)) -> dict:
    """Consumes a valid one-time reset token and sets the new password."""
    token = str(payload.get("token", ""))
    new_password = str(payload.get("new_password", ""))
    if len(new_password) < 8:
        raise HTTPException(status_code=422, detail="Password must be at least 8 characters")
    record = _consume_token(db, token, "password_reset")
    if record is None:
        raise HTTPException(status_code=422, detail="Invalid or expired reset token")
    user = db.get(User, record.user_id)
    if user is None or not user.is_active:
        raise HTTPException(status_code=422, detail="Invalid or expired reset token")
    user.password_hash = hash_password(new_password)
    db.commit()
    return {"status": "password_reset"}


@router.post("/verify-email")
def verify_email(payload: dict, db: Session = Depends(get_db)) -> dict:
    """Consumes a one-time verification token and marks the account verified."""
    token = str(payload.get("token", ""))
    record = _consume_token(db, token, "email_verification")
    if record is None:
        raise HTTPException(status_code=422, detail="Invalid or expired verification token")
    user = db.get(User, record.user_id)
    if user is None:
        raise HTTPException(status_code=422, detail="Invalid or expired verification token")
    user.email_verified = True
    db.commit()
    return {"status": "verified"}
