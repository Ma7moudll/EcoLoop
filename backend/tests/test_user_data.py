"""User-data endpoints: /users/me, waste history, impact, leaderboard,
challenges — matching the Flutter data-repository contract."""
from __future__ import annotations

from .conftest import confirm_event


def confirm_deposit(client, auth, prediction, **kwargs) -> dict:
    r = client.post(
        "/api/v1/deposit/session",
        headers=auth,
        json={"ai_prediction_id": prediction["prediction_id"], "station_id": "st-001"},
    )
    assert r.status_code == 200, r.text
    session = r.json()
    r = client.post("/api/v1/deposit/callback/event",
                    json=confirm_event(session["operation_id"], **kwargs))
    assert r.status_code == 200, r.text
    return session


def test_impact_after_one_deposit(client, auth, plastic_prediction):
    confirm_deposit(client, auth, plastic_prediction,
                    position=1, weight=18.4, stable=True, beam=True, mech=True, carriage=1)
    r = client.get("/api/v1/impact", headers=auth)
    assert r.status_code == 200
    body = r.json()
    assert body["items_recycled"] == 1
    assert body["total_points"] == 50  # 45 seeded + 5 awarded
    assert body["recycled_kg"] > 0
    by_class = {c["waste_class"]: c for c in body["breakdown"]}
    assert by_class["plastic"]["count"] == 1


def test_waste_history_lists_audit_trail(client, auth, plastic_prediction):
    session = confirm_deposit(client, auth, plastic_prediction,
                              position=1, weight=18.4, stable=True, beam=True, mech=True, carriage=1)
    r = client.get("/api/v1/waste/history", headers=auth)
    assert r.status_code == 200
    items = r.json()["items"]
    assert any(i["operation_id"] == session["operation_id"] for i in items)
    recovered = [i for i in items if i["operation_id"] == session["operation_id"]][0]
    assert recovered["predicted_class"] == "plastic"
    assert recovered["points_awarded"] == 5


def test_rejected_deposit_still_in_history_with_zero_points(client, auth, plastic_prediction):
    r = client.post(
        "/api/v1/deposit/session",
        headers=auth,
        json={"ai_prediction_id": plastic_prediction["prediction_id"], "station_id": "st-001"},
    )
    session = r.json()
    client.post("/api/v1/deposit/callback/event",
                json=confirm_event(session["operation_id"], position=2, weight=18.4,
                                   stable=True, beam=True, mech=True, carriage=2))
    r = client.get("/api/v1/waste/history", headers=auth)
    items = r.json()["items"]
    ev = [i for i in items if i["operation_id"] == session["operation_id"]][0]
    assert ev["points_awarded"] == 0  # rejected: audited but zero points


def test_leaderboard_aggregates_students_and_faculties(client, auth, plastic_prediction):
    confirm_deposit(client, auth, plastic_prediction,
                    position=1, weight=18.4, stable=True, beam=True, mech=True, carriage=1)
    r = client.get("/api/v1/leaderboard?scope=students", headers=auth)
    entries = r.json()["entries"]
    top = entries[0]
    assert top["name"] == "Demo Student"
    assert top["points"] == 50  # 45 seeded + 5
    assert top["id"]  # Flutter LeaderEntry.id
    rf = client.get("/api/v1/leaderboard/faculties", headers=auth)
    fac = [e for e in rf.json()["entries"] if e["id"] == "engineering"][0]
    assert fac["points"] == 50


def test_challenges_endpoint(client, auth):
    r = client.get("/api/v1/challenges", headers=auth)
    assert r.status_code == 200
    assert isinstance(r.json()["items"], list)


def test_users_me_returns_user_wrapper(client, auth):
    r = client.get("/api/v1/users/me", headers=auth)
    assert r.status_code == 200
    assert "user" in r.json()