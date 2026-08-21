"""Admin surface (T23): every mutating admin route requires the admin role;
students get 403; admins manage stations/users/challenges."""
from __future__ import annotations

import pytest

from app.database import SessionLocal
from app.models import User
from app.security import hash_password


def _make_admin(email="admin@recycle.vision") -> None:
    with SessionLocal() as db:
        if db.query(User).filter(User.email == email).first() is None:
            db.add(
                User(
                    id="u-admin",
                    email=email,
                    student_code="S-ADMIN",
                    name="Admin",
                    password_hash=hash_password("admin-pass-123"),
                    faculty_id="engineering",
                    points=0,
                    role="admin",
                )
            )
            db.commit()


@pytest.fixture
def admin_auth(client):
    _make_admin()
    r = client.post(
        "/api/v1/auth/login",
        json={"email": "admin@recycle.vision", "password": "admin-pass-123"},
    )
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def test_student_cannot_create_station(client, auth):
    r = client.post(
        "/api/v1/admin/stations",
        headers=auth,
        json={"station_code": "ST-099", "name": "Sneaky Station"},
    )
    assert r.status_code == 403


def test_student_cannot_list_users(client, auth):
    assert client.get("/api/v1/admin/users", headers=auth).status_code == 403


def test_admin_can_create_and_patch_station(client, admin_auth):
    r = client.post(
        "/api/v1/admin/stations",
        headers=admin_auth,
        json={"station_code": "ST-002", "name": "Library Station"},
    )
    assert r.status_code == 200, r.text
    station = r.json()
    r = client.patch(
        f"/api/v1/admin/stations/{station['id']}",
        headers=admin_auth,
        json={"status": "online"},
    )
    assert r.status_code == 200
    assert r.json()["status"] == "online"


def test_admin_can_list_and_deactivate_user(client, admin_auth):
    users = client.get("/api/v1/admin/users", headers=admin_auth).json()["items"]
    assert any(u["email"] == "demo@recycle.vision" for u in users)

    target = next(u for u in users if u["email"] == "demo@recycle.vision")
    r = client.patch(
        f"/api/v1/admin/users/{target['id']}",
        headers=admin_auth,
        json={"is_active": False},
    )
    assert r.status_code == 200
    assert r.json()["is_active"] is False

    # A deactivated user cannot log in.
    login = client.post(
        "/api/v1/auth/login",
        json={"email": "demo@recycle.vision", "password": "demo123"},
    )
    assert login.status_code == 403


def test_admin_cannot_deactivate_themselves(client, admin_auth):
    me = client.get("/api/v1/auth/me", headers=admin_auth).json()["user"]
    r = client.patch(
        f"/api/v1/admin/users/{me['id']}",
        headers=admin_auth,
        json={"is_active": False},
    )
    assert r.status_code in {400, 422}


def test_admin_can_create_challenge(client, admin_auth):
    r = client.post(
        "/api/v1/admin/challenges",
        headers=admin_auth,
        json={
            "title": "Metal Month",
            "description": "Deposit 5kg of metal",
            "waste_class": "metal",
            "target_kg": 5.0,
            "reward_points": 100,
        },
    )
    assert r.status_code == 200, r.text
