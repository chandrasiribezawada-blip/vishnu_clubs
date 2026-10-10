from sqlalchemy import select

from app.core.security import hash_password
from app.models.entities import (
    Club,
    ClubCoordinator,
    ClubJoinRequest,
    ClubMembership,
    JoinRequestStatus,
    Notification,
    User,
    UserRole,
)
from test_auth_membership import API, auth_header, issue_tokens, register


def _coordinator_and_club(client, suffix: str = "coordinator"):
    with client.app.state.testing_session_factory() as db:
        club = Club(name=f"{suffix.title()} Club", category="Technical")
        coordinator = User(
            email=f"{suffix}@example.edu",
            full_name=f"{suffix.title()} User",
            password_hash=hash_password("secure-coordinator-password"),
            role=UserRole.CLUB_MEMBER_COORDINATOR,
        )
        db.add_all([club, coordinator])
        db.flush()
        db.add(ClubCoordinator(user_id=coordinator.id, club_id=club.id))
        db.commit()
        return club.id, coordinator.id


def test_coordinator_club_routes_require_assignment_and_authentication(client):
    club_id, coordinator_id = _coordinator_and_club(client)
    tokens = issue_tokens(client, coordinator_id)

    response = client.get(f"{API}/coordinator/club", headers=auth_header(tokens))
    assert response.status_code == 200, response.text
    assert response.json()["id"] == club_id
    assert client.get(f"{API}/coordinator/club").status_code == 401

    student_tokens = register(client, "coordinator-route-student")
    assert client.get(
        f"{API}/coordinator/club", headers=auth_header(student_tokens)
    ).status_code == 403

    other_club_id, other_coordinator_id = _coordinator_and_club(client, "other")
    other_tokens = issue_tokens(client, other_coordinator_id)
    assert client.patch(
        f"{API}/coordinator/club",
        headers=auth_header(other_tokens),
        json={"name": "Attempted Cross Club Edit"},
    ).status_code == 200
    assert client.get(
        f"{API}/coordinator/club", headers=auth_header(other_tokens)
    ).json()["id"] == other_club_id


def test_coordinator_approval_creates_membership_and_notification(client):
    club_id, coordinator_id = _coordinator_and_club(client)
    coordinator_tokens = issue_tokens(client, coordinator_id)
    student_tokens = register(client, "pending-applicant")
    submitted = client.post(
        f"{API}/clubs/{club_id}/join-requests",
        headers=auth_header(student_tokens),
        json={
            "reason": "I want to contribute to campus projects.",
            "skills": "Python, design",
            "experience": "Built two class projects",
        },
    )
    assert submitted.status_code == 201, submitted.text
    request_id = submitted.json()["id"]

    request_list = client.get(
        f"{API}/coordinator/club/join-requests",
        headers=auth_header(coordinator_tokens),
    )
    assert request_list.status_code == 200
    assert request_list.json()[0]["id"] == request_id
    approved = client.post(
        f"{API}/coordinator/club/join-requests/{request_id}/approve",
        headers=auth_header(coordinator_tokens),
        json={"note": "Welcome"},
    )
    assert approved.status_code == 200, approved.text
    assert approved.json()["status"] == "APPROVED"

    with client.app.state.testing_session_factory() as db:
        request = db.get(ClubJoinRequest, request_id)
        assert request is not None
        assert request.status == JoinRequestStatus.APPROVED
        assert db.scalar(
            select(ClubMembership).where(
                ClubMembership.student_id == request.student_id,
                ClubMembership.club_id == club_id,
                ClubMembership.ended_at.is_(None),
            )
        ) is not None
        assert db.scalar(
            select(Notification).where(
                Notification.recipient_id == request.student_id,
                Notification.title == "Membership request approved",
            )
        ) is not None

    memberships = client.get(
        f"{API}/me/memberships", headers=auth_header(student_tokens)
    )
    assert memberships.status_code == 200
    assert memberships.json()[0]["club_id"] == club_id
    assert client.post(
        f"{API}/coordinator/club/join-requests/{request_id}/reject",
        headers=auth_header(coordinator_tokens),
        json={},
    ).status_code == 409


def test_join_request_decisions_reject_another_clubs_requests(client):
    first_club, first_coordinator = _coordinator_and_club(client, "first")
    _, second_coordinator = _coordinator_and_club(client, "second")
    student_tokens = register(client, "cross-club-applicant")
    coordinator_tokens = issue_tokens(client, second_coordinator)
    submitted = client.post(
        f"{API}/clubs/{first_club}/join-requests",
        headers=auth_header(student_tokens),
        json={
            "reason": "I want to help organize technical sessions.",
            "skills": "Programming",
            "experience": "Volunteer",
        },
    )
    assert submitted.status_code == 201
    denied = client.post(
        f"{API}/coordinator/club/join-requests/{submitted.json()['id']}/approve",
        headers=auth_header(coordinator_tokens),
        json={},
    )
    assert denied.status_code == 403
    with client.app.state.testing_session_factory() as db:
        request = db.get(ClubJoinRequest, submitted.json()["id"])
        assert request is not None
        assert request.status == JoinRequestStatus.PENDING


def test_admin_can_create_and_filter_clubs_and_coordinators(client):
    _, coordinator_id = _coordinator_and_club(client, "admin-existing")
    with client.app.state.testing_session_factory() as db:
        admin = User(
            email="workflow-admin@example.edu",
            full_name="Workflow Admin",
            password_hash=hash_password("secure-admin-password"),
            role=UserRole.CLUB_ADMIN,
        )
        db.add(admin)
        db.commit()
        admin_id = admin.id
    admin_tokens = issue_tokens(client, admin_id)

    created = client.post(
        f"{API}/admin/clubs",
        headers=auth_header(admin_tokens),
        json={"name": "New Admin Club", "category": "Arts"},
    )
    assert created.status_code == 201, created.text
    new_club_id = created.json()["id"]
    filtered = client.get(
        f"{API}/admin/users?role=CLUB_MEMBER_COORDINATOR",
        headers=auth_header(admin_tokens),
    )
    assert filtered.status_code == 200
    assert all(user["role"] == "CLUB_MEMBER_COORDINATOR" for user in filtered.json())
    assert any(user["id"] == str(coordinator_id) for user in filtered.json())

    assigned = client.post(
        f"{API}/admin/coordinators",
        headers=auth_header(admin_tokens),
        json={
            "email": "new-coordinator@example.edu",
            "full_name": "New Coordinator",
            "password": "another-secure-password",
            "club_id": new_club_id,
        },
    )
    assert assigned.status_code == 201, assigned.text
    assert assigned.json()["role"] == "CLUB_MEMBER_COORDINATOR"
    deactivated = client.patch(
        f"{API}/admin/clubs/{new_club_id}/activation?active=false",
        headers=auth_header(admin_tokens),
    )
    assert deactivated.status_code == 200
    assert deactivated.json()["is_active"] is False


def test_admin_endpoints_reject_unauthenticated_and_non_admin_users(client):
    _, coordinator_id = _coordinator_and_club(client, "admin-access")
    coordinator_tokens = issue_tokens(client, coordinator_id)
    student_tokens = register(client, "admin-access-student")

    assert client.get(f"{API}/admin/clubs").status_code == 401
    assert client.get(
        f"{API}/admin/clubs", headers=auth_header(student_tokens)
    ).status_code == 403
    assert client.get(
        f"{API}/admin/dashboard", headers=auth_header(coordinator_tokens)
    ).status_code == 403


def test_seed_roles_is_repeatable_and_uses_existing_password_hashing(
    client, monkeypatch
):
    import scripts.seed_roles as seed_roles

    club_id, _ = _coordinator_and_club(client, "seed-club")
    monkeypatch.setattr(
        seed_roles,
        "get_session_factory",
        lambda: client.app.state.testing_session_factory,
    )
    for name, value in {
        "SEED_ADMIN_EMAIL": "seed-admin@example.edu",
        "SEED_ADMIN_PASSWORD": "a-secure-seed-admin-password",
        "SEED_COORD_EMAIL": "seed-coord@example.edu",
        "SEED_COORD_PASSWORD": "a-secure-seed-coordinator-password",
        "SEED_COORD_CLUB_NAME": "Seed-club Club",
    }.items():
        monkeypatch.setenv(name, value)

    assert seed_roles.main() == 0
    assert seed_roles.main() == 0
    with client.app.state.testing_session_factory() as db:
        admin = db.scalar(select(User).where(User.email == "seed-admin@example.edu"))
        coordinator = db.scalar(
            select(User).where(User.email == "seed-coord@example.edu")
        )
        assert admin is not None and admin.role == UserRole.CLUB_ADMIN
        assert coordinator is not None
        assert coordinator.role == UserRole.CLUB_MEMBER_COORDINATOR
        assignments = db.scalars(
            select(ClubCoordinator).where(
                ClubCoordinator.user_id == coordinator.id,
                ClubCoordinator.club_id == club_id,
                ClubCoordinator.revoked_at.is_(None),
            )
        ).all()
        assert len(assignments) == 1
