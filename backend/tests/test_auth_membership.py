from sqlalchemy import select

from app.core.config import Settings
from app.core.security import (
    create_access_token,
    create_refresh_token,
    digest_token,
    hash_password,
)
from app.models.entities import (
    AuditLog,
    Club,
    ClubCoordinator,
    ClubEvent,
    ClubJoinRequest,
    ClubMembership,
    EventAttendance,
    EventRegistration,
    EventRegistrationStatus,
    EventStatus,
    EventTicket,
    Notification,
    JoinRequestDecision,
    JoinRequestStatus,
    RefreshSession,
    User,
    UserRole,
)
from app.scripts.seed_clubs import CLUB_NAMES

API = "/api/v1"
TEST_SETTINGS = Settings(
    database_url="sqlite+pysqlite:///:memory:",
    jwt_secret_key="test-secret-key-with-at-least-thirty-two-characters",
)


def register(client, suffix: str = "one") -> dict:
    response = client.post(
        f"{API}/auth/register",
        json={
            "full_name": f"Student {suffix}",
            "email": f"{suffix}@example.edu",
            "registration_number": f"REG-{suffix}",
            "department": "Engineering",
            "year": "First",
            "phone_number": "+15551234567",
            "password": "correct-horse-battery",
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def auth_header(tokens: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


def issue_tokens(client, user_id) -> dict[str, str]:
    with client.app.state.testing_session_factory() as db:
        user = db.get(User, user_id)
        assert user is not None
        from uuid import uuid4

        session_id = uuid4()
        access, _ = create_access_token(
            TEST_SETTINGS, user.id, user.role.value, session_id
        )
        refresh, expiry = create_refresh_token(TEST_SETTINGS, user.id, session_id)
        db.add(
            RefreshSession(
                id=session_id,
                user_id=user.id,
                refresh_token_digest=digest_token(refresh),
                expires_at=expiry,
            )
        )
        db.commit()
    return {"access_token": access, "refresh_token": refresh}


def test_student_registration_and_refresh_token_rotation(client):
    tokens = register(client)
    assert tokens["user"]["role"] == "STUDENT"
    assert client.get(f"{API}/auth/me", headers=auth_header(tokens)).status_code == 200

    rotated = client.post(
        f"{API}/auth/refresh", json={"refresh_token": tokens["refresh_token"]}
    )
    assert rotated.status_code == 200, rotated.text
    assert rotated.json()["refresh_token"] != tokens["refresh_token"]
    assert client.get(f"{API}/auth/me", headers=auth_header(tokens)).status_code == 200
    assert client.get(
        f"{API}/auth/me", headers=auth_header(rotated.json())
    ).status_code == 200

    replayed = client.post(
        f"{API}/auth/refresh", json={"refresh_token": tokens["refresh_token"]}
    )
    assert replayed.status_code == 401
    assert client.get(
        f"{API}/auth/me", headers=auth_header(rotated.json())
    ).status_code == 401


def test_registration_never_grants_a_client_selected_privileged_role(client):
    tokens = register(client)
    assert tokens["user"]["role"] == "STUDENT"
    escalation_attempt = client.post(
        f"{API}/auth/register",
        json={
            "full_name": "Other Name",
            "email": "elevated@example.edu",
            "registration_number": "REG-OTHER",
            "department": "Engineering",
            "year": "First",
            "phone_number": "+15551234567",
            "password": "correct-horse-battery",
            "role": "CLUB_ADMIN",
        },
    )
    assert escalation_attempt.status_code == 422
    weak_password = client.post(
        f"{API}/auth/register",
        json={
            "full_name": "Short Password",
            "email": "short@example.edu",
            "registration_number": "REG-SHORT",
            "department": "Engineering",
            "year": "First",
            "phone_number": "+15551234567",
            "password": "weak",
            "role": "CLUB_ADMIN",
        },
    )
    assert weak_password.status_code == 422
    with client.app.state.testing_session_factory() as db:
        assert db.scalar(select(User).where(User.email == "elevated@example.edu")) is None


def test_single_login_returns_the_server_assigned_role_for_each_account_type(client):
    student_tokens = register(client, "role-student")
    assert student_tokens["user"]["role"] == "STUDENT"

    register(client, "role-coordinator")
    admin_password = "a-secure-admin-password"
    with client.app.state.testing_session_factory() as db:
        coordinator = db.scalar(
            select(User).where(User.email == "role-coordinator@example.edu")
        )
        assert coordinator is not None
        coordinator.role = UserRole.CLUB_MEMBER_COORDINATOR
        club = Club(name="Assigned Coordinator Club")
        admin = User(
            email="role-admin@example.edu",
            full_name="Role Admin",
            password_hash=hash_password(admin_password),
            role=UserRole.CLUB_ADMIN,
        )
        db.add_all([club, admin])
        db.flush()
        db.add(ClubCoordinator(user_id=coordinator.id, club_id=club.id))
        db.commit()

    for email, password, expected_role in (
        ("role-student@example.edu", "correct-horse-battery", "STUDENT"),
        ("role-coordinator@example.edu", "correct-horse-battery", "CLUB_MEMBER_COORDINATOR"),
        ("role-admin@example.edu", admin_password, "CLUB_ADMIN"),
    ):
        response = client.post(
            f"{API}/auth/login",
            json={"email": email, "password": password},
        )
        assert response.status_code == 200, response.text
        tokens = response.json()
        assert tokens["user"]["role"] == expected_role
        current_user = client.get(
            f"{API}/auth/me", headers=auth_header(tokens)
        )
        assert current_user.status_code == 200
        assert current_user.json()["role"] == expected_role

    role_spoof = client.post(
        f"{API}/auth/login",
        json={
            "email": "role-student@example.edu",
            "password": "correct-horse-battery",
            "role": "CLUB_ADMIN",
        },
    )
    assert role_spoof.status_code == 422


def test_seeded_clubs_are_listed_from_the_database(client, monkeypatch):
    from app.scripts import seed_clubs

    monkeypatch.setattr(
        seed_clubs,
        "get_session_factory",
        lambda: client.app.state.testing_session_factory,
    )
    seed_clubs.seed()
    seed_clubs.seed()

    assert len(CLUB_NAMES) == 23
    assert len(set(CLUB_NAMES)) == 23
    with client.app.state.testing_session_factory() as db:
        clubs = db.scalars(select(Club).order_by(Club.id)).all()
        assert len(clubs) == 23
        assert all(club.category for club in clubs)

    response = client.get(f"{API}/clubs")
    assert response.status_code == 200
    assert len(response.json()) == 23
    assert {item["name"] for item in response.json()} == set(CLUB_NAMES)
    assert {item["category"] for item in response.json()} == {
        "Social Impact",
        "Technical",
        "Environment",
        "General",
        "Arts & Culture",
        "Literary",
    }


def test_membership_decision_requires_assignment_and_persists_membership(client):
    student_tokens = register(client, "member")
    coordinator_tokens = register(client, "coordinator")
    other_coordinator_tokens = register(client, "other-coordinator")

    with client.app.state.testing_session_factory() as db:
        club = Club(name="Test Club")
        other_club = Club(name="Other Club")
        db.add_all([club, other_club])
        admin = User(
            email="admin@example.edu",
            full_name="Club Admin",
            password_hash=hash_password("a-secure-admin-password"),
            role=UserRole.CLUB_ADMIN,
        )
        db.add(admin)
        db.commit()
        db.refresh(club)
        db.refresh(other_club)
        coordinator_id = db.scalar(
            select(User.id).where(User.email == "coordinator@example.edu")
        )
        other_coordinator_id = db.scalar(
            select(User.id).where(User.email == "other-coordinator@example.edu")
        )
        admin_id = admin.id
        club_id = club.id
        other_club_id = other_club.id

    admin_tokens = issue_tokens(client, admin_id)
    assigned = client.post(
        f"{API}/admin/clubs/{club_id}/coordinators",
        headers=auth_header(admin_tokens),
        json={"user_id": str(coordinator_id)},
    )
    assert assigned.status_code == 204, assigned.text
    other_assigned = client.post(
        f"{API}/admin/clubs/{other_club_id}/coordinators",
        headers=auth_header(admin_tokens),
        json={"user_id": str(other_coordinator_id)},
    )
    assert other_assigned.status_code == 204, other_assigned.text

    invalid_application = client.post(
        f"{API}/clubs/{club_id}/join-requests",
        headers=auth_header(student_tokens),
        json={"reason": " " * 25, "skills": " "},
    )
    assert invalid_application.status_code == 422

    created = client.post(
        f"{API}/clubs/{club_id}/join-requests",
        headers=auth_header(student_tokens),
        json={
            "reason": "I want to contribute to club projects.",
            "skills": "Design",
        },
    )
    assert created.status_code == 201, created.text
    assert created.json()["status"] == "PENDING"
    request_id = created.json()["id"]
    duplicate_pending = client.post(
        f"{API}/clubs/{club_id}/join-requests",
        headers=auth_header(student_tokens),
        json={
            "reason": "I want to contribute to club projects.",
            "skills": "Design",
        },
    )
    assert duplicate_pending.status_code == 409
    student_cannot_list = client.get(
        f"{API}/clubs/{club_id}/join-requests",
        headers=auth_header(student_tokens),
    )
    assert student_cannot_list.status_code == 403
    student_cannot_list_assignments = client.get(
        f"{API}/me/coordinator-clubs",
        headers=auth_header(student_tokens),
    )
    assert student_cannot_list_assignments.status_code == 403

    followed = client.post(
        f"{API}/clubs/{club_id}/follow", headers=auth_header(student_tokens)
    )
    assert followed.status_code == 204
    repeated_follow = client.post(
        f"{API}/clubs/{club_id}/follow", headers=auth_header(student_tokens)
    )
    assert repeated_follow.status_code == 204
    followed_clubs = client.get(
        f"{API}/me/followed-clubs", headers=auth_header(student_tokens)
    )
    assert [club["id"] for club in followed_clubs.json()] == [club_id]

    coordinator = client.post(
        f"{API}/auth/login",
        json={
            "email": "coordinator@example.edu",
            "password": "correct-horse-battery",
        },
    )
    assert coordinator.status_code == 200, coordinator.text
    coordinator_tokens = coordinator.json()
    coordinator_clubs = client.get(
        f"{API}/me/coordinator-clubs",
        headers=auth_header(coordinator_tokens),
    )
    assert [item["id"] for item in coordinator_clubs.json()] == [club_id]
    pending = client.get(
        f"{API}/clubs/{club_id}/join-requests",
        headers=auth_header(coordinator_tokens),
    )
    assert pending.status_code == 200
    assert [row["id"] for row in pending.json()] == [request_id]
    dashboard = client.get(
        f"{API}/coordinator/dashboard",
        headers=auth_header(coordinator_tokens),
    )
    assert dashboard.status_code == 200, dashboard.text
    assert [item["club_id"] for item in dashboard.json()["assigned_clubs"]] == [
        club_id
    ]

    denied = client.get(
        f"{API}/clubs/{club_id}/join-requests",
        headers=auth_header(other_coordinator_tokens),
    )
    assert denied.status_code == 403
    cross_club_decision = client.post(
        f"{API}/join-requests/{request_id}/approve",
        headers=auth_header(other_coordinator_tokens),
        json={},
    )
    assert cross_club_decision.status_code == 403
    student_decision = client.post(
        f"{API}/join-requests/{request_id}/approve",
        headers=auth_header(student_tokens),
        json={},
    )
    assert student_decision.status_code == 403
    unassigned_club = client.get(
        f"{API}/clubs/{other_club_id}/join-requests",
        headers=auth_header(coordinator_tokens),
    )
    assert unassigned_club.status_code == 403

    approved = client.post(
        f"{API}/join-requests/{request_id}/approve",
        headers=auth_header(coordinator_tokens),
        json={"note": "Welcome"},
    )
    assert approved.status_code == 200, approved.text
    assert approved.json()["status"] == "APPROVED"
    repeated_approval = client.post(
        f"{API}/join-requests/{request_id}/approve",
        headers=auth_header(coordinator_tokens),
        json={},
    )
    assert repeated_approval.status_code == 409
    invalid_transition = client.post(
        f"{API}/join-requests/{request_id}/reject",
        headers=auth_header(coordinator_tokens),
        json={},
    )
    assert invalid_transition.status_code == 409
    pending_after_decision = client.get(
        f"{API}/clubs/{club_id}/join-requests",
        headers=auth_header(coordinator_tokens),
    )
    assert pending_after_decision.json() == []

    memberships = client.get(
        f"{API}/me/memberships", headers=auth_header(student_tokens)
    )
    assert memberships.status_code == 200
    assert memberships.json()[0]["club_id"] == club_id

    duplicate = client.post(
        f"{API}/clubs/{club_id}/join-requests",
        headers=auth_header(student_tokens),
        json={
            "reason": "I want to contribute to club projects.",
            "skills": "Design",
        },
    )
    assert duplicate.status_code == 409
    with client.app.state.testing_session_factory() as db:
        assert len(db.scalars(select(ClubMembership)).all()) == 1
        assert len(db.scalars(select(AuditLog)).all()) == 4
        assert len(db.scalars(select(JoinRequestDecision)).all()) == 1

    unfollowed = client.delete(
        f"{API}/clubs/{club_id}/follow", headers=auth_header(student_tokens)
    )
    assert unfollowed.status_code == 204
    assert client.get(
        f"{API}/me/followed-clubs", headers=auth_header(student_tokens)
    ).json() == []
    assert client.get(
        f"{API}/me/memberships", headers=auth_header(student_tokens)
    ).json()[0]["club_id"] == club_id


def test_coordinator_dashboard_summarizes_only_active_assigned_clubs(client):
    from datetime import UTC, datetime, timedelta

    register(client, "summary-coordinator")
    register(client, "summary-member")
    register(client, "summary-pending")
    student_tokens = register(client, "summary-unauthorized")
    admin_password = "a-secure-admin-password"

    with client.app.state.testing_session_factory() as db:
        coordinator = db.scalar(
            select(User).where(User.email == "summary-coordinator@example.edu")
        )
        active_member = db.scalar(
            select(User).where(User.email == "summary-member@example.edu")
        )
        pending_student = db.scalar(
            select(User).where(User.email == "summary-pending@example.edu")
        )
        assert coordinator is not None
        assert active_member is not None
        assert pending_student is not None
        coordinator.role = UserRole.CLUB_MEMBER_COORDINATOR

        managed_club = Club(name="Coordinator Summary Club")
        revoked_club = Club(name="Revoked Summary Club")
        db.add_all([managed_club, revoked_club])
        db.flush()
        now = datetime.now(UTC)
        db.add_all(
            [
                ClubCoordinator(
                    user_id=coordinator.id,
                    club_id=managed_club.id,
                ),
                ClubCoordinator(
                    user_id=coordinator.id,
                    club_id=revoked_club.id,
                    revoked_at=now,
                ),
            ]
        )

        approved_request = ClubJoinRequest(
            student_id=active_member.id,
            club_id=managed_club.id,
            reason="I would like to help with club activities.",
            skills="Organization",
            status=JoinRequestStatus.APPROVED,
        )
        pending_request = ClubJoinRequest(
            student_id=pending_student.id,
            club_id=managed_club.id,
            reason="I would like to contribute to this club.",
            skills="Design",
            status=JoinRequestStatus.PENDING,
        )
        db.add_all([approved_request, pending_request])
        db.flush()
        db.add(
            ClubMembership(
                student_id=active_member.id,
                club_id=managed_club.id,
                join_request_id=approved_request.id,
            )
        )

        event = ClubEvent(
            club_id=managed_club.id,
            title="Coordinator Summary Event",
            description=None,
            category="General",
            eligibility=None,
            poster_url=None,
            start_at=now + timedelta(days=2),
            end_at=now + timedelta(days=2, hours=1),
            registration_opens_at=now,
            registration_closes_at=now + timedelta(days=1),
            venue="Campus",
            latitude=None,
            longitude=None,
            capacity=20,
            status=EventStatus.PUBLISHED,
            created_by=coordinator.id,
        )
        db.add(event)
        db.flush()
        db.add(
            EventRegistration(
                event_id=event.id,
                student_id=active_member.id,
                status=EventRegistrationStatus.REGISTERED,
            )
        )
        admin = User(
            email="summary-admin@example.edu",
            full_name="Summary Admin",
            password_hash=hash_password(admin_password),
            role=UserRole.CLUB_ADMIN,
        )
        db.add(admin)
        db.commit()
        coordinator_id = coordinator.id
        admin_id = admin.id
        managed_club_id = managed_club.id

    headers = auth_header(issue_tokens(client, coordinator_id))
    response = client.get(f"{API}/coordinator/dashboard", headers=headers)
    assert response.status_code == 200, response.text
    dashboard = response.json()
    assert len(dashboard["assigned_clubs"]) == 1
    assert dashboard["assigned_clubs"][0] == {
        "club_id": managed_club_id,
        "club_name": "Coordinator Summary Club",
        "category": None,
        "active_members": 1,
        "pending_join_requests": 1,
        "events": 1,
        "active_event_registrations": 1,
    }
    assert dashboard["active_members"] == 1
    assert dashboard["pending_join_requests"] == 1
    assert dashboard["events"] == 1
    assert dashboard["active_event_registrations"] == 1

    assert client.get(
        f"{API}/coordinator/dashboard",
        headers=auth_header(student_tokens),
    ).status_code == 403
    assert client.get(
        f"{API}/coordinator/dashboard",
        headers=auth_header(issue_tokens(client, admin_id)),
    ).status_code == 403


def test_reject_request_can_be_reapplied_but_decision_is_recorded_once(client):
    student_tokens = register(client, "retry")
    coordinator_tokens = register(client, "retry-coordinator")
    with client.app.state.testing_session_factory() as db:
        club = Club(name="Retry Club")
        coordinator = db.scalar(
            select(User).where(User.email == "retry-coordinator@example.edu")
        )
        assert coordinator is not None
        coordinator.role = UserRole.CLUB_MEMBER_COORDINATOR
        db.add(club)
        db.flush()
        db.add(ClubCoordinator(user_id=coordinator.id, club_id=club.id))
        db.commit()
        club_id = club.id

    headers = auth_header(student_tokens)
    request_body = {
        "reason": "I want to contribute to club projects.",
        "skills": "Design",
    }
    submitted = client.post(
        f"{API}/clubs/{club_id}/join-requests",
        headers=headers,
        json=request_body,
    )
    assert submitted.status_code == 201, submitted.text
    request_id = submitted.json()["id"]
    rejected = client.post(
        f"{API}/join-requests/{request_id}/reject",
        headers=auth_header(coordinator_tokens),
        json={"note": "Please apply again next term"},
    )
    assert rejected.status_code == 200, rejected.text
    assert rejected.json()["status"] == "REJECTED"
    student_status = client.get(
        f"{API}/me/join-requests",
        headers=headers,
    )
    assert student_status.status_code == 200
    assert student_status.json()[0]["status"] == "REJECTED"
    approve_rejected = client.post(
        f"{API}/join-requests/{request_id}/approve",
        headers=auth_header(coordinator_tokens),
        json={},
    )
    reject_rejected = client.post(
        f"{API}/join-requests/{request_id}/reject",
        headers=auth_header(coordinator_tokens),
        json={},
    )
    assert approve_rejected.status_code == 409
    assert reject_rejected.status_code == 409

    resubmitted = client.post(
        f"{API}/clubs/{club_id}/join-requests",
        headers=headers,
        json=request_body,
    )
    assert resubmitted.status_code == 201, resubmitted.text
    assert resubmitted.json()["id"] != request_id
    with client.app.state.testing_session_factory() as db:
        assert len(db.scalars(select(ClubJoinRequest)).all()) == 2
        assert len(db.scalars(select(JoinRequestDecision)).all()) == 1
        assert len(db.scalars(select(ClubMembership)).all()) == 0


def _event_payload(*, capacity: int = 1, days: int = 2) -> dict[str, object]:
    from datetime import UTC, datetime, timedelta

    now = datetime.now(UTC)
    start = now + timedelta(days=days)
    return {
        "title": "Verified Test Event",
        "description": "A database-backed test event.",
        "category": "Workshop",
        "start_at": start.isoformat(),
        "end_at": (start + timedelta(hours=2)).isoformat(),
        "registration_opens_at": (now - timedelta(minutes=1)).isoformat(),
        "registration_closes_at": (start - timedelta(hours=1)).isoformat(),
        "venue": "Verified campus venue",
        "capacity": capacity,
    }


def _assign_coordinator(client, suffix: str, club_name: str):
    tokens = register(client, suffix)
    with client.app.state.testing_session_factory() as db:
        coordinator = db.scalar(
            select(User).where(User.email == f"{suffix}@example.edu")
        )
        assert coordinator is not None
        coordinator.role = UserRole.CLUB_MEMBER_COORDINATOR
        club = Club(name=club_name)
        db.add(club)
        db.flush()
        db.add(ClubCoordinator(user_id=coordinator.id, club_id=club.id))
        db.commit()
        club_id = club.id
    return tokens, club_id


def test_event_draft_publish_registration_cancel_and_capacity(client):
    coordinator, club_id = _assign_coordinator(client, "event-coordinator", "Event Club")
    student = register(client, "event-student")
    second_student = register(client, "event-student-two")
    created = client.post(
        f"{API}/clubs/{club_id}/events",
        headers=auth_header(coordinator),
        json=_event_payload(capacity=1),
    )
    assert created.status_code == 201, created.text
    event = created.json()
    assert event["status"] == "DRAFT"
    assert event["registration_count"] == 0
    event_id = event["id"]
    assert client.get(f"{API}/events").json() == []
    assert client.get(f"{API}/events/{event_id}").status_code == 404

    published = client.post(
        f"{API}/events/{event_id}/publish",
        headers=auth_header(coordinator),
    )
    assert published.status_code == 200, published.text
    assert published.json()["status"] == "PUBLISHED"
    assert len(client.get(f"{API}/events").json()) == 1

    registered = client.post(
        f"{API}/events/{event_id}/registrations",
        headers=auth_header(student),
    )
    assert registered.status_code == 201, registered.text
    assert registered.json()["status"] == "REGISTERED"
    duplicate = client.post(
        f"{API}/events/{event_id}/registrations",
        headers=auth_header(student),
    )
    assert duplicate.status_code == 409
    full = client.post(
        f"{API}/events/{event_id}/registrations",
        headers=auth_header(second_student),
    )
    assert full.status_code == 409

    mine = client.get(f"{API}/me/events", headers=auth_header(student))
    assert mine.status_code == 200
    assert mine.json()[0]["registration_status"] == "REGISTERED"
    assert mine.json()[0]["id"] == event_id

    cancelled = client.delete(
        f"{API}/events/{event_id}/registrations/me",
        headers=auth_header(student),
    )
    assert cancelled.status_code == 200
    assert cancelled.json()["status"] == "CANCELLED"
    reregistered = client.post(
        f"{API}/events/{event_id}/registrations",
        headers=auth_header(second_student),
    )
    assert reregistered.status_code == 201

    with client.app.state.testing_session_factory() as db:
        registrations = db.scalars(
            select(EventRegistration).where(EventRegistration.event_id == event_id)
        ).all()
        assert len(registrations) == 2
        assert sum(
            row.status == EventRegistrationStatus.REGISTERED for row in registrations
        ) == 1

    event_cancelled = client.post(
        f"{API}/events/{event_id}/cancel",
        headers=auth_header(coordinator),
    )
    assert event_cancelled.status_code == 200
    assert event_cancelled.json()["status"] == "CANCELLED"
    second_student_events = client.get(
        f"{API}/me/events",
        headers=auth_header(second_student),
    )
    assert second_student_events.json()[0]["registration_status"] == "CANCELLED"
    with client.app.state.testing_session_factory() as db:
        assert len(db.scalars(select(Notification)).all()) == 3


def test_event_authorization_validation_and_cancellation(client):
    coordinator, club_id = _assign_coordinator(
        client, "event-owner", "Owned Event Club"
    )
    other_coordinator, other_club_id = _assign_coordinator(
        client, "other-event-owner", "Other Event Club"
    )
    student = register(client, "event-unauthorized-student")
    data = _event_payload()
    naive_datetime = dict(data)
    naive_datetime["start_at"] = "2030-01-01T10:00:00"
    assert client.post(
        f"{API}/clubs/{club_id}/events",
        headers=auth_header(coordinator),
        json=naive_datetime,
    ).status_code == 422
    invalid_coordinates = dict(data)
    invalid_coordinates.update(latitude=91, longitude=181)
    assert client.post(
        f"{API}/clubs/{club_id}/events",
        headers=auth_header(coordinator),
        json=invalid_coordinates,
    ).status_code == 422

    student_create = client.post(
        f"{API}/clubs/{club_id}/events",
        headers=auth_header(student),
        json=data,
    )
    assert student_create.status_code == 403
    cross_club_create = client.post(
        f"{API}/clubs/{other_club_id}/events",
        headers=auth_header(coordinator),
        json=data,
    )
    assert cross_club_create.status_code == 403

    created = client.post(
        f"{API}/clubs/{club_id}/events",
        headers=auth_header(coordinator),
        json=data,
    )
    assert created.status_code == 201, created.text
    event_id = created.json()["id"]
    assert client.post(
        f"{API}/events/{event_id}/publish",
        headers=auth_header(other_coordinator),
    ).status_code == 403
    assert client.patch(
        f"{API}/events/{event_id}",
        headers=auth_header(other_coordinator),
        json={"title": "Unauthorized edit"},
    ).status_code == 403

    invalid_edit = client.patch(
        f"{API}/events/{event_id}",
        headers=auth_header(coordinator),
        json={"capacity": 0},
    )
    assert invalid_edit.status_code == 422
    assert client.post(
        f"{API}/events/{event_id}/publish",
        headers=auth_header(coordinator),
    ).status_code == 200
    assert client.post(
        f"{API}/events/{event_id}/cancel",
        headers=auth_header(coordinator),
    ).status_code == 200
    assert client.post(
        f"{API}/events/{event_id}/publish",
        headers=auth_header(coordinator),
    ).status_code == 409
    assert client.post(
        f"{API}/events/{event_id}/registrations",
        headers=auth_header(student),
    ).status_code == 409

    listing = client.get(
        f"{API}/clubs/{club_id}/events/manage",
        headers=auth_header(coordinator),
    )
    assert listing.status_code == 200
    assert listing.json()[0]["status"] == "CANCELLED"


def test_event_registration_window_and_registration_ownership(client):
    coordinator, club_id = _assign_coordinator(
        client, "window-owner", "Window Event Club"
    )
    student = register(client, "window-student")
    other_student = register(client, "window-other-student")
    payload = _event_payload()
    from datetime import UTC, datetime, timedelta

    payload["registration_opens_at"] = (
        datetime.now(UTC) + timedelta(days=1)
    ).isoformat()
    payload["registration_closes_at"] = (
        datetime.now(UTC) + timedelta(days=2)
    ).isoformat()
    payload["start_at"] = (datetime.now(UTC) + timedelta(days=3)).isoformat()
    payload["end_at"] = (datetime.now(UTC) + timedelta(days=3, hours=2)).isoformat()
    created = client.post(
        f"{API}/clubs/{club_id}/events",
        headers=auth_header(coordinator),
        json=payload,
    )
    assert created.status_code == 201, created.text
    event_id = created.json()["id"]
    assert client.post(
        f"{API}/events/{event_id}/publish",
        headers=auth_header(coordinator),
    ).status_code == 200
    too_early = client.post(
        f"{API}/events/{event_id}/registrations",
        headers=auth_header(student),
    )
    assert too_early.status_code == 409

    with client.app.state.testing_session_factory() as db:
        event = db.get(ClubEvent, event_id)
        assert event is not None
        event.registration_opens_at = datetime.now(UTC) - timedelta(minutes=1)
        event.registration_closes_at = datetime.now(UTC) + timedelta(days=1)
        db.commit()

    registered = client.post(
        f"{API}/events/{event_id}/registrations",
        headers=auth_header(student),
    )
    assert registered.status_code == 201
    not_owner_cancel = client.delete(
        f"{API}/events/{event_id}/registrations/me",
        headers=auth_header(other_student),
    )
    assert not_owner_cancel.status_code == 404
    owner_cancel = client.delete(
        f"{API}/events/{event_id}/registrations/me",
        headers=auth_header(student),
    )
    assert owner_cancel.status_code == 200


def test_event_pass_check_in_and_attendance_history(client):
    from datetime import UTC, datetime, timedelta
    from hashlib import sha256

    coordinator, club_id = _assign_coordinator(
        client, "attendance-owner", "Attendance Club"
    )
    other_coordinator, _ = _assign_coordinator(
        client, "attendance-outsider", "Other Attendance Club"
    )
    student = register(client, "attendance-student")
    created = client.post(
        f"{API}/clubs/{club_id}/events",
        headers=auth_header(coordinator),
        json=_event_payload(),
    )
    assert created.status_code == 201, created.text
    event_id = created.json()["id"]
    assert client.post(
        f"{API}/events/{event_id}/publish",
        headers=auth_header(coordinator),
    ).status_code == 200
    assert client.post(
        f"{API}/events/{event_id}/pass",
        headers=auth_header(student),
    ).status_code == 403
    assert client.post(
        f"{API}/events/{event_id}/registrations",
        headers=auth_header(student),
    ).status_code == 201

    pass_response = client.post(
        f"{API}/events/{event_id}/pass",
        headers=auth_header(student),
    )
    assert pass_response.status_code == 201, pass_response.text
    assert pass_response.headers["cache-control"] == "no-store, private"
    token = pass_response.json()["ticket_token"]
    assert len(token) >= 32
    assert client.post(
        f"{API}/events/{event_id}/attendance/check-in",
        headers=auth_header(coordinator),
        json={"ticket_token": token},
    ).status_code == 409
    with client.app.state.testing_session_factory() as db:
        ticket = db.scalar(select(EventTicket))
        assert ticket is not None
        assert ticket.token_hash == sha256(token.encode()).hexdigest()
        assert ticket.token_hash != token
        event = db.get(ClubEvent, event_id)
        assert event is not None
        event.start_at = datetime.now(UTC) - timedelta(minutes=5)
        event.end_at = datetime.now(UTC) + timedelta(hours=1)
        event.registration_opens_at = datetime.now(UTC) - timedelta(hours=2)
        event.registration_closes_at = datetime.now(UTC) - timedelta(hours=1)
        ticket.expires_at = datetime.now(UTC) + timedelta(hours=1)
        db.commit()

    wrong_event = client.post(
        f"{API}/clubs/{club_id}/events",
        headers=auth_header(coordinator),
        json={**_event_payload(), "title": "Different Event"},
    )
    assert wrong_event.status_code == 201
    wrong_event_id = wrong_event.json()["id"]
    assert client.post(
        f"{API}/events/{wrong_event_id}/publish",
        headers=auth_header(coordinator),
    ).status_code == 200
    assert client.post(
        f"{API}/events/{wrong_event_id}/attendance/check-in",
        headers=auth_header(coordinator),
        json={"ticket_token": token},
    ).status_code == 409
    assert client.post(
        f"{API}/events/{event_id}/attendance/check-in",
        headers=auth_header(other_coordinator),
        json={"ticket_token": token},
    ).status_code == 403
    assert client.post(
        f"{API}/events/{event_id}/attendance/check-in",
        headers=auth_header(student),
        json={"ticket_token": token},
    ).status_code == 403
    assert client.post(
        f"{API}/events/{event_id}/attendance/check-in",
        headers=auth_header(coordinator),
        json={"ticket_token": "not-a-valid-ticket-token-value-123456"},
    ).status_code == 409

    checked_in = client.post(
        f"{API}/events/{event_id}/attendance/check-in",
        headers=auth_header(coordinator),
        json={"ticket_token": token},
    )
    assert checked_in.status_code == 200, checked_in.text
    assert checked_in.json()["result"] == "ATTENDANCE_RECORDED"
    summary = client.get(
        f"{API}/events/{event_id}/attendance/summary",
        headers=auth_header(coordinator),
    )
    assert summary.status_code == 200
    assert summary.json() == {
        "event_id": event_id,
        "registered_count": 1,
        "attended_count": 1,
        "not_attended_count": 0,
    }
    participants = client.get(
        f"{API}/events/{event_id}/participants",
        headers=auth_header(coordinator),
    )
    assert participants.status_code == 200
    assert participants.json()[0]["attended"] is True
    assert client.get(
        f"{API}/events/{event_id}/attendance/summary",
        headers=auth_header(other_coordinator),
    ).status_code == 403
    assert client.post(
        f"{API}/events/{event_id}/attendance/check-in",
        headers=auth_header(coordinator),
        json={"ticket_token": token},
    ).status_code == 409
    assert client.post(
        f"{API}/events/{event_id}/pass",
        headers=auth_header(student),
    ).status_code == 409
    history = client.get(f"{API}/me/attendance", headers=auth_header(student))
    assert history.status_code == 200
    assert history.json()[0]["event_title"] == "Verified Test Event"
    with client.app.state.testing_session_factory() as db:
        assert len(db.scalars(select(EventAttendance)).all()) == 1


def test_notifications_are_private_and_can_be_marked_read(client):
    student = register(client, "notification-recipient")
    other_student = register(client, "notification-other")
    with client.app.state.testing_session_factory() as db:
        recipient = db.scalar(
            select(User).where(User.email == "notification-recipient@example.edu")
        )
        assert recipient is not None
        notification = Notification(
            recipient_id=recipient.id,
            title="Request update",
            message="Your request was approved.",
        )
        db.add(notification)
        db.commit()
        notification_id = notification.id

    headers = auth_header(student)
    listed = client.get(f"{API}/me/notifications", headers=headers)
    assert listed.status_code == 200
    assert len(listed.json()) == 1
    assert listed.json()[0]["read_at"] is None
    assert client.patch(
        f"{API}/me/notifications/{notification_id}/read",
        headers=auth_header(other_student),
    ).status_code == 404

    marked = client.patch(
        f"{API}/me/notifications/{notification_id}/read",
        headers=headers,
    )
    assert marked.status_code == 200
    assert marked.json()["read_at"] is not None
    again = client.patch(
        f"{API}/me/notifications/{notification_id}/read",
        headers=headers,
    )
    assert again.status_code == 200


def test_admin_dashboard_and_management_endpoints_are_admin_only(client):
    student = register(client, "admin-endpoint-student")
    assert client.get(
        f"{API}/admin/dashboard",
        headers=auth_header(student),
    ).status_code == 403
    with client.app.state.testing_session_factory() as db:
        db.add(Club(name="Admin Dashboard Club"))
        admin = User(
            email="dashboard-admin@example.edu",
            full_name="Dashboard Admin",
            password_hash=hash_password("a-secure-admin-password"),
            role=UserRole.CLUB_ADMIN,
        )
        db.add(admin)
        db.commit()
        admin_id = admin.id
    headers = auth_header(issue_tokens(client, admin_id))
    dashboard = client.get(f"{API}/admin/dashboard", headers=headers)
    assert dashboard.status_code == 200
    assert dashboard.json()["active_clubs"] == 1
    assert client.get(f"{API}/admin/users", headers=headers).status_code == 200
    assert client.get(f"{API}/admin/coordinators", headers=headers).status_code == 200


def test_announcements_are_persistent_scoped_and_notify_relevant_students(client):
    coordinator, club_id = _assign_coordinator(
        client, "announcement-coordinator", "Announcement Club"
    )
    other_coordinator, other_club_id = _assign_coordinator(
        client, "announcement-other-coordinator", "Other Announcement Club"
    )
    student = register(client, "announcement-follower")
    unrelated = register(client, "announcement-unrelated")
    assert client.post(
        f"{API}/clubs/{club_id}/follow",
        headers=auth_header(student),
    ).status_code == 204

    created = client.post(
        f"{API}/clubs/{club_id}/announcements",
        headers=auth_header(coordinator),
        json={
            "title": "Club meeting",
            "body": "Join the club meeting this Friday.",
            "publish": False,
        },
    )
    assert created.status_code == 201, created.text
    announcement_id = created.json()["id"]
    assert created.json()["status"] == "DRAFT"
    assert client.get(
        f"{API}/announcements",
        headers=auth_header(student),
    ).json() == []
    assert client.get(
        f"{API}/clubs/{club_id}/announcements/manage",
        headers=auth_header(other_coordinator),
    ).status_code == 403
    assert client.post(
        f"{API}/announcements/{announcement_id}/publish",
        headers=auth_header(other_coordinator),
    ).status_code == 403

    published = client.post(
        f"{API}/announcements/{announcement_id}/publish",
        headers=auth_header(coordinator),
    )
    assert published.status_code == 200, published.text
    assert published.json()["status"] == "PUBLISHED"
    relevant = client.get(
        f"{API}/announcements",
        headers=auth_header(student),
    )
    assert len(relevant.json()) == 1
    assert relevant.json()[0]["title"] == "Club meeting"
    club_feed = client.get(f"{API}/clubs/{club_id}/announcements")
    assert club_feed.status_code == 200
    assert club_feed.json()[0]["title"] == "Club meeting"
    assert client.get(
        f"{API}/announcements",
        headers=auth_header(unrelated),
    ).json() == []
    notifications = client.get(
        f"{API}/me/notifications",
        headers=auth_header(student),
    )
    assert any(
        item["title"] == "Club meeting"
        and item["target_path"] == "/announcements"
        for item in notifications.json()
    )
    assert client.get(
        f"{API}/clubs/{other_club_id}/announcements/manage",
        headers=auth_header(coordinator),
    ).status_code == 403


def test_admin_can_publish_platform_wide_announcement(client):
    student = register(client, "platform-announcement-student")
    with client.app.state.testing_session_factory() as db:
        admin = User(
            email="announcement-admin@example.edu",
            full_name="Announcement Admin",
            password_hash=hash_password("a-secure-admin-password"),
            role=UserRole.CLUB_ADMIN,
        )
        db.add(admin)
        db.commit()
        admin_id = admin.id
    admin_headers = auth_header(issue_tokens(client, admin_id))
    created = client.post(
        f"{API}/admin/announcements",
        headers=admin_headers,
        json={
            "title": "Campus update",
            "body": "A verified campus update.",
            "publish": True,
        },
    )
    assert created.status_code == 201, created.text
    assert created.json()["club_id"] is None
    visible = client.get(f"{API}/announcements", headers=auth_header(student))
    assert visible.status_code == 200
    assert visible.json()[0]["title"] == "Campus update"
    notifications = client.get(
        f"{API}/me/notifications",
        headers=auth_header(student),
    )
    assert any(item["title"] == "Campus update" for item in notifications.json())


def test_event_pass_rejects_expired_revoked_and_cancelled_registration(client):
    from datetime import UTC, datetime, timedelta

    coordinator, club_id = _assign_coordinator(
        client, "attendance-state-owner", "Attendance State Club"
    )
    student = register(client, "attendance-state-student")
    created = client.post(
        f"{API}/clubs/{club_id}/events",
        headers=auth_header(coordinator),
        json=_event_payload(),
    )
    event_id = created.json()["id"]
    assert client.post(
        f"{API}/events/{event_id}/publish",
        headers=auth_header(coordinator),
    ).status_code == 200
    assert client.post(
        f"{API}/events/{event_id}/registrations",
        headers=auth_header(student),
    ).status_code == 201
    ticket = client.post(
        f"{API}/events/{event_id}/pass",
        headers=auth_header(student),
    ).json()["ticket_token"]

    with client.app.state.testing_session_factory() as db:
        event = db.get(ClubEvent, event_id)
        ticket_row = db.scalar(select(EventTicket))
        registration = db.scalar(select(EventRegistration))
        assert event is not None and ticket_row is not None and registration is not None
        event.start_at = datetime.now(UTC) - timedelta(minutes=5)
        event.end_at = datetime.now(UTC) + timedelta(hours=1)
        event.registration_opens_at = datetime.now(UTC) - timedelta(hours=2)
        event.registration_closes_at = datetime.now(UTC) - timedelta(hours=1)
        ticket_row.expires_at = datetime.now(UTC) - timedelta(seconds=1)
        db.commit()
    expired = client.post(
        f"{API}/events/{event_id}/attendance/check-in",
        headers=auth_header(coordinator),
        json={"ticket_token": ticket},
    )
    assert expired.status_code == 409

    ticket = client.post(
        f"{API}/events/{event_id}/pass",
        headers=auth_header(student),
    ).json()["ticket_token"]
    with client.app.state.testing_session_factory() as db:
        ticket_row = db.scalar(select(EventTicket))
        assert ticket_row is not None
        ticket_row.revoked_at = datetime.now(UTC)
        db.commit()
    assert client.post(
        f"{API}/events/{event_id}/attendance/check-in",
        headers=auth_header(coordinator),
        json={"ticket_token": ticket},
    ).status_code == 409

    cancelled_event = client.post(
        f"{API}/clubs/{club_id}/events",
        headers=auth_header(coordinator),
        json={**_event_payload(), "title": "Cancelled Attendance Event"},
    )
    assert cancelled_event.status_code == 201
    cancelled_event_id = cancelled_event.json()["id"]
    assert client.post(
        f"{API}/events/{cancelled_event_id}/publish",
        headers=auth_header(coordinator),
    ).status_code == 200
    assert client.post(
        f"{API}/events/{cancelled_event_id}/registrations",
        headers=auth_header(student),
    ).status_code == 201
    cancelled_ticket = client.post(
        f"{API}/events/{cancelled_event_id}/pass",
        headers=auth_header(student),
    ).json()["ticket_token"]
    assert client.post(
        f"{API}/events/{cancelled_event_id}/cancel",
        headers=auth_header(coordinator),
    ).status_code == 200
    assert client.post(
        f"{API}/events/{cancelled_event_id}/attendance/check-in",
        headers=auth_header(coordinator),
        json={"ticket_token": cancelled_ticket},
    ).status_code == 409
    with client.app.state.testing_session_factory() as db:
        cancelled_row = db.scalar(
            select(EventTicket)
            .join(EventRegistration)
            .where(EventRegistration.event_id == cancelled_event_id)
        )
        assert cancelled_row is not None
        assert cancelled_row.revoked_at is not None

    ticket = client.post(
        f"{API}/events/{event_id}/pass",
        headers=auth_header(student),
    ).json()["ticket_token"]
    with client.app.state.testing_session_factory() as db:
        registration = db.scalar(select(EventRegistration))
        assert registration is not None
        registration.status = EventRegistrationStatus.CANCELLED
        db.commit()
    assert client.post(
        f"{API}/events/{event_id}/attendance/check-in",
        headers=auth_header(coordinator),
        json={"ticket_token": ticket},
    ).status_code == 409


def test_logout_revokes_the_session(client):
    tokens = register(client, "logout")
    response = client.post(
        f"{API}/auth/logout",
        headers=auth_header(tokens),
        json={"refresh_token": tokens["refresh_token"]},
    )
    assert response.status_code == 200
    assert client.get(f"{API}/auth/me", headers=auth_header(tokens)).status_code == 401
