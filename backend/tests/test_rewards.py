"""Rewards marketplace (T24): catalog browsing, atomic idempotent redemption,
code vs cash flows, admin fulfillment queue, and points integrity under
concurrency. The balance can never go negative and a retried redeem can
never double-spend."""
from __future__ import annotations

import threading

import pytest

from app.database import SessionLocal
from app.models import User
from app.security import hash_password
from app.services.reward_service import RewardError


@pytest.fixture
def student(client):
    """Fresh student with 120 points — enough for coffee (60) + printing (80)
    is NOT affordable; tests control exact balances via _set_points."""
    with SessionLocal() as db:
        db.add(
            User(
                id="u-reward",
                email="reward@recycle.vision",
                student_code="S-REWARD",
                name="Reward Student",
                password_hash=hash_password("reward-pass-123"),
                faculty_id="ENGINEERING",
                points=0,
            )
        )
        db.commit()
    r = client.post(
        "/api/v1/auth/login",
        json={"email": "reward@recycle.vision", "password": "reward-pass-123"},
    )
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def _set_points(user_id: str, points: int) -> None:
    with SessionLocal() as db:
        user = db.get(User, user_id)
        assert user is not None
        user.points = points
        db.commit()


def _balance(user_id: str = "u-reward") -> int:
    with SessionLocal() as db:
        return int(db.get(User, user_id).points)


# -- catalog -------------------------------------------------------------------


def test_catalog_lists_seeded_rewards_with_balance(client, student):
    r = client.get("/api/v1/rewards", headers=student)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["balance"] == 0
    ids = {item["id"] for item in body["rewards"]}
    assert {"rw-vodafone-10", "rw-instapay-25", "rw-mix-coffee-20", "rw-copy-center-30"} <= ids
    vodafone = [i for i in body["rewards"] if i["id"] == "rw-vodafone-10"][0]
    assert vodafone["requires_destination"] is True
    assert vodafone["category"] == "cash"


def test_catalog_requires_auth(client):
    r = client.get("/api/v1/rewards")
    assert r.status_code == 401


# -- code flow (coffee discount) -------------------------------------------------


def test_redeem_deducts_points_and_issues_code(client, student):
    _set_points("u-reward", 60)
    r = client.post(
        "/api/v1/rewards/rw-mix-coffee-20/redeem",
        headers=student,
        json={"idempotency_key": "11111111-1111-1111-1111-111111111111"},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["balance"] == 0
    rd = body["redemption"]
    assert rd["status"] == "available"
    assert rd["redemption_code"] and rd["redemption_code"].startswith("ECO-")
    assert _balance() == 0


def test_insufficient_balance_is_refused_without_state_change(client, student):
    _set_points("u-reward", 59)
    r = client.post(
        "/api/v1/rewards/rw-mix-coffee-20/redeem",
        headers=student,
        json={"idempotency_key": "22222222-2222-2222-2222-222222222222"},
    )
    assert r.status_code == 409
    assert "enough points" in r.json()["error"].lower()
    assert _balance() == 59  # untouched


def test_idempotent_retry_returns_original_redemption(client, student):
    _set_points("u-reward", 200)
    key = "33333333-3333-3333-3333-333333333333"
    payload = {"idempotency_key": key}
    first = client.post("/api/v1/rewards/rw-mix-coffee-20/redeem", headers=student, json=payload)
    retry = client.post("/api/v1/rewards/rw-mix-coffee-20/redeem", headers=student, json=payload)
    other = client.post("/api/v1/rewards/rw-copy-center-30/redeem", headers=student, json=payload)
    assert first.status_code == 200 and retry.status_code == 200
    assert first.json()["redemption"]["id"] == retry.json()["redemption"]["id"]
    # Same key against a DIFFERENT reward also returns the original — never a second spend.
    assert other.status_code == 200
    assert other.json()["redemption"]["id"] == first.json()["redemption"]["id"]
    assert _balance() == 200 - 60  # one deduction only


def test_parallel_redeems_cannot_overspend_balance(client, student):
    """10 concurrent redemptions of a 60-point reward against a 240-point
    balance: exactly 4 succeed, the rest are refused, final balance is
    exactly 0 — no lost updates, nothing negative."""
    _set_points("u-reward", 240)
    results: list[int] = []
    lock = threading.Lock()

    def fire(i: int) -> None:
        from app.services.reward_service import redeem

        with SessionLocal() as db:
            try:
                redeem(db, user_id="u-reward", reward_id="rw-mix-coffee-20",
                       idempotency_key=f"parallel-{i:03d}-aaaaaaaaaaaa")
                outcome = 200
            except RewardError as exc:
                outcome = exc.status_code
        with lock:
            results.append(outcome)

    threads = [threading.Thread(target=fire, args=(i,)) for i in range(10)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    ok = results.count(200)
    assert ok == 4, results
    assert _balance() == 0  # 4 x 60 spent; nothing lost, nothing negative


def test_codes_are_unique_per_redemption(client, student):
    _set_points("u-reward", 600)
    codes = set()
    for i in range(3):
        r = client.post(
            "/api/v1/rewards/rw-mix-coffee-20/redeem",
            headers=student,
            json={"idempotency_key": f"unique-codes-{i}-aaaaaaaaaa"},
        )
        assert r.status_code == 200, r.text
        codes.add(r.json()["redemption"]["redemption_code"])
    assert len(codes) == 3


def test_cancel_available_code_refunds_points(client, student):
    _set_points("u-reward", 60)
    r = client.post(
        "/api/v1/rewards/rw-mix-coffee-20/redeem",
        headers=student,
        json={"idempotency_key": "cancel-0001-aaaaaaaaaaaa"},
    )
    rd_id = r.json()["redemption"]["id"]
    cancel = client.post(f"/api/v1/rewards/redemptions/{rd_id}/cancel", headers=student)
    assert cancel.status_code == 200, cancel.text
    assert cancel.json()["redemption"]["status"] == "cancelled"
    assert cancel.json()["balance"] == 60


def test_cancel_twice_or_on_used_is_refused(client, student):
    _set_points("u-reward", 60)
    r = client.post(
        "/api/v1/rewards/rw-mix-coffee-20/redeem",
        headers=student,
        json={"idempotency_key": "cancel-0002-aaaaaaaaaaaa"},
    )
    rd_id = r.json()["redemption"]["id"]
    client.post(f"/api/v1/rewards/redemptions/{rd_id}/cancel", headers=student)
    again = client.post(f"/api/v1/rewards/redemptions/{rd_id}/cancel", headers=student)
    assert again.status_code == 422


def test_user_cannot_see_or_cancel_someone_elses_redemption(client, student, auth):
    _set_points("u-reward", 60)
    r = client.post(
        "/api/v1/rewards/rw-mix-coffee-20/redeem",
        headers=student,
        json={"idempotency_key": "cross-user-1-aaaaaaaaaaa"},
    )
    rd_id = r.json()["redemption"]["id"]
    # `auth` fixture is the demo user — a different account.
    foreign_get = client.get("/api/v1/rewards/redemptions", headers=auth)
    ids = [i["id"] for i in foreign_get.json()["redemptions"]]
    assert rd_id not in ids
    foreign_cancel = client.post(f"/api/v1/rewards/redemptions/{rd_id}/cancel", headers=auth)
    assert foreign_cancel.status_code == 404


def test_cash_reward_requires_destination(client, student):
    _set_points("u-reward", 100)
    r = client.post(
        "/api/v1/rewards/rw-vodafone-10/redeem",
        headers=student,
        json={"idempotency_key": "cash-nodest-1-aaaaaaaaa"},
    )
    assert r.status_code == 422
    assert "payout number" in r.json()["error"].lower()
    assert _balance() == 100


# -- cash flow + admin queue ------------------------------------------------------


@pytest.fixture
def admin_auth(client):
    with SessionLocal() as db:
        if db.query(User).filter(User.email == "admin@recycle.vision").first() is None:
            db.add(
                User(
                    id="u-admin",
                    email="admin@recycle.vision",
                    student_code="S-ADMIN",
                    name="Admin",
                    password_hash=hash_password("admin-pass-123"),
                    faculty_id="ENGINEERING",
                    points=0,
                    role="admin",
                )
            )
            db.commit()
    r = client.post(
        "/api/v1/auth/login",
        json={"email": "admin@recycle.vision", "password": "admin-pass-123"},
    )
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def _redeem_vodafone(client, student, key="cash-flow-1-aaaaaaaaaaa") -> str:
    _set_points("u-reward", 100)
    r = client.post(
        "/api/v1/rewards/rw-vodafone-10/redeem",
        headers=student,
        json={"idempotency_key": key, "destination": "01012345678"},
    )
    assert r.status_code == 200, r.text
    return r.json()["redemption"]["id"]


def test_student_cannot_access_admin_queue(client, student):
    r = client.get("/api/v1/admin/rewards/redemptions", headers=student)
    assert r.status_code == 403


def test_cash_redemption_lands_pending_in_admin_queue(client, student, admin_auth):
    rd_id = _redeem_vodafone(client, student)
    r = client.get("/api/v1/admin/rewards/redemptions?status=pending", headers=admin_auth)
    assert r.status_code == 200, r.text
    items = [i for i in r.json()["items"] if i["id"] == rd_id]
    assert len(items) == 1
    item = items[0]
    assert item["status"] == "pending"
    assert item["destination_masked"].startswith("010")
    assert "*" in item["destination_masked"] and not item["destination_masked"].endswith(
        "01012345678"
    )  # masked, not raw
    assert item["student"]["email"] == "reward@recycle.vision"


def test_approve_then_fulfill_flow(client, student, admin_auth):
    rd_id = _redeem_vodafone(client, student)
    approve = client.post(
        f"/api/v1/admin/rewards/redemptions/{rd_id}/approve",
        headers=admin_auth,
        json={"admin_note": ""},
    )
    assert approve.status_code == 200 and approve.json()["status"] == "approved"
    fulfill = client.post(
        f"/api/v1/admin/rewards/redemptions/{rd_id}/fulfill",
        headers=admin_auth,
        json={"admin_note": "sent via Vodafone Cash portal"},
    )
    assert fulfill.status_code == 200 and fulfill.json()["status"] == "fulfilled"
    mine = client.get("/api/v1/rewards/redemptions", headers=student).json()["redemptions"]
    assert mine[0]["status"] == "fulfilled"


def test_reject_refunds_points_exactly_once(client, student, admin_auth):
    rd_id = _redeem_vodafone(client, student, key="reject-flow-1-aaaaaaaaa")
    before = _balance()
    reject = client.post(
        f"/api/v1/admin/rewards/redemptions/{rd_id}/reject",
        headers=admin_auth,
        json={"admin_note": "wallet unreachable"},
    )
    assert reject.status_code == 200 and reject.json()["status"] == "rejected"
    after_first = _balance()
    assert after_first == before + 100
    # Rejecting again must not double-refund.
    reject_again = client.post(
        f"/api/v1/admin/rewards/redemptions/{rd_id}/reject",
        headers=admin_auth,
        json={"admin_note": "retry"},
    )
    assert reject_again.status_code == 409
    assert _balance() == after_first


def test_fulfilled_redemption_cannot_be_rejected_after(client, student, admin_auth):
    rd_id = _redeem_vodafone(client, student, key="fulfill-lock-1-aaaaaaaa")
    client.post(f"/api/v1/admin/rewards/redemptions/{rd_id}/fulfill", headers=admin_auth, json={})
    reject = client.post(
        f"/api/v1/admin/rewards/redemptions/{rd_id}/reject", headers=admin_auth, json={}
    )
    assert reject.status_code == 409


# -- catalog management ------------------------------------------------------------


def test_admin_can_create_update_deactivate_reward(client, admin_auth):
    create = client.post(
        "/api/v1/admin/rewards",
        headers=admin_auth,
        json={
            "category": "discount",
            "name": "Cafeteria Combo",
            "points_cost": 150,
            "value_label": "15% OFF",
            "stock": 5,
        },
    )
    assert create.status_code == 200, create.text
    reward_id = create.json()["id"]

    patch = client.patch(
        f"/api/v1/admin/rewards/{reward_id}",
        headers=admin_auth,
        json={
            "category": "discount",
            "name": "Cafeteria Combo",
            "points_cost": 140,
            "value_label": "15% OFF",
            "is_active": False,
            "stock": 5,
        },
    )
    assert patch.status_code == 200 and patch.json()["is_active"] is False

    # Deactivated rewards vanish from the student catalog.
    catalog_ids = [
        i["id"] for i in client.get("/api/v1/rewards", headers=admin_auth).json()["rewards"]
    ]
    assert reward_id not in catalog_ids


def test_cash_reward_requires_destination_flag(client, admin_auth):
    r = client.post(
        "/api/v1/admin/rewards",
        headers=admin_auth,
        json={"category": "cash", "name": "Bad Cash", "points_cost": 10, "value_label": "1 EGP"},
    )
    assert r.status_code == 422


def test_delete_blocked_when_history_exists(client, student, admin_auth):
    rd_id = _redeem_vodafone(client, student, key="del-guard-1-aaaaaaaaaaa")
    del_ok = client.delete("/api/v1/admin/rewards/rw-instapay-25", headers=admin_auth)
    assert del_ok.status_code == 200
    del_used = client.delete("/api/v1/admin/rewards/rw-vodafone-10", headers=admin_auth)
    assert del_used.status_code == 409
    assert "deactivate" in del_used.json()["error"].lower()
    # Redemption history still intact.
    mine = client.get("/api/v1/rewards/redemptions", headers=student).json()["redemptions"]
    assert any(i["id"] == rd_id for i in mine)


def test_stock_is_atomic_and_blocks_sold_out(client, student, admin_auth):
    create = client.post(
        "/api/v1/admin/rewards",
        headers=admin_auth,
        json={
            "category": "food",
            "name": "Limited Snack",
            "points_cost": 10,
            "value_label": "Snack",
            "stock": 1,
        },
    )
    reward_id = create.json()["id"]

    with SessionLocal() as db:
        db.add_all(
            [
                User(
                    id=f"u-stock-{i}",
                    email=f"stock{i}@recycle.vision",
                    student_code=f"S-STOCK{i}",
                    name=f"Stock {i}",
                    password_hash=hash_password("stock-pass-123"),
                    faculty_id="ENGINEERING",
                    points=50,
                )
                for i in range(2)
            ]
        )
        db.commit()

    tokens = []
    for i in range(2):
        r = client.post(
            "/api/v1/auth/login",
            json={"email": f"stock{i}@recycle.vision", "password": "stock-pass-123"},
        )
        tokens.append({"Authorization": f"Bearer {r.json()['token']}"})

    outcomes = []
    for tok in tokens:
        r = client.post(
            f"/api/v1/rewards/{reward_id}/redeem",
            headers=tok,
            json={"idempotency_key": f"stock-race-{tokens.index(tok)}-aaaaaaa"},
        )
        outcomes.append(r.status_code)
    assert sorted(outcomes) == [200, 422]  # one wins, one sees sold out
