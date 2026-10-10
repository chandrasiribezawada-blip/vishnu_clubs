from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, HTTPException, Response, status
from pydantic import BaseModel, ConfigDict, EmailStr, Field
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError

from app.api.dependencies import CoordinatorUser, DbSession
from app.models.entities import (
    Club,
    ClubCoordinator,
    ClubEvent,
    ClubJoinRequest,
    ClubMembership,
    ClubFollower,
    JoinRequestStatus,
    StudentProfile,
    User,
    Notification,
    AuditLog,
    EventRegistration,
    EventRegistrationStatus,
    utc_now,
)
from app.schemas.clubs import DecisionRequest, JoinRequestResponse
from app.schemas.events import EventCreate, EventUpdate
from app.schemas.announcements import AnnouncementCreate, AnnouncementResponse
from app.services import announcement_service, club_service, event_service

router = APIRouter(prefix="/coordinator", tags=["coordinator"])


class ManagedClubResponse(BaseModel):
    id: int
    name: str
    category: str | None
    description: str | None
    objectives: str | None
    contact_email: str | None
    is_active: bool
    member_count: int
    follower_count: int


class ManagedClubUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=200)
    category: str | None = Field(default=None, max_length=100)
    description: str | None = None
    objectives: str | None = None
    contact_email: EmailStr | None = None

    model_config = ConfigDict(extra="forbid")


class ClubMemberResponse(BaseModel):
    user_id: UUID
    full_name: str
    email: EmailStr
    registration_number: str | None
    department: str | None
    year: str | None
    phone_number: str | None
    member_since: datetime


def _assigned_club(db, coordinator: User) -> Club:
    club = db.scalar(
        select(Club)
        .join(ClubCoordinator, ClubCoordinator.club_id == Club.id)
        .where(
            ClubCoordinator.user_id == coordinator.id,
            ClubCoordinator.revoked_at.is_(None),
        )
        .order_by(ClubCoordinator.assigned_at.desc())
    )
    if club is None:
        raise HTTPException(status_code=404, detail="No club is assigned to this coordinator")
    return club


def _require_club_assignment(db, coordinator: User, club_id: int) -> Club:
    club = db.get(Club, club_id)
    assigned = db.scalar(
        select(ClubCoordinator.id).where(
            ClubCoordinator.user_id == coordinator.id,
            ClubCoordinator.club_id == club_id,
            ClubCoordinator.revoked_at.is_(None),
        )
    )
    if club is None or assigned is None:
        raise HTTPException(status_code=403, detail="Club access denied")
    return club


def _managed_club_response(db, club: Club) -> dict[str, object]:
    return {
        "id": club.id,
        "name": club.name,
        "category": club.category,
        "description": club.description,
        "objectives": club.objectives,
        "contact_email": club.contact_email,
        "is_active": club.is_active,
        "member_count": db.scalar(
            select(func.count(ClubMembership.id)).where(
                ClubMembership.club_id == club.id,
                ClubMembership.ended_at.is_(None),
            )
        )
        or 0,
        "follower_count": db.scalar(
            select(func.count(ClubFollower.id)).where(ClubFollower.club_id == club.id)
        )
        or 0,
    }


@router.get("/club", response_model=ManagedClubResponse)
def get_managed_club(db: DbSession, coordinator: CoordinatorUser):
    return _managed_club_response(db, _assigned_club(db, coordinator))


@router.get("/club/stats", response_model=dict[str, int])
def managed_club_stats(db: DbSession, coordinator: CoordinatorUser):
    club = _assigned_club(db, coordinator)
    return {
        "members": db.scalar(
            select(func.count(ClubMembership.id)).where(
                ClubMembership.club_id == club.id,
                ClubMembership.ended_at.is_(None),
            )
        )
        or 0,
        "pending_join_requests": db.scalar(
            select(func.count(ClubJoinRequest.id)).where(
                ClubJoinRequest.club_id == club.id,
                ClubJoinRequest.status == JoinRequestStatus.PENDING,
            )
        )
        or 0,
        "upcoming_events": db.scalar(
            select(func.count(ClubEvent.id)).where(
                ClubEvent.club_id == club.id,
                ClubEvent.start_at >= datetime.now(UTC),
            )
        )
        or 0,
    }


@router.get("/club/members", response_model=list[ClubMemberResponse])
def managed_club_members(db: DbSession, coordinator: CoordinatorUser):
    club = _assigned_club(db, coordinator)
    rows = db.execute(
        select(ClubMembership, User, StudentProfile)
        .join(User, User.id == ClubMembership.student_id)
        .outerjoin(StudentProfile, StudentProfile.user_id == User.id)
        .where(
            ClubMembership.club_id == club.id,
            ClubMembership.ended_at.is_(None),
        )
        .order_by(User.full_name)
    ).all()
    return [
        {
            "user_id": user.id,
            "full_name": user.full_name,
            "email": user.email,
            "registration_number": profile.registration_number if profile else None,
            "department": profile.department if profile else None,
            "year": profile.year if profile else None,
            "phone_number": profile.phone_number if profile else None,
            "member_since": membership.created_at,
        }
        for membership, user, profile in rows
    ]


@router.delete(
    "/club/members/{user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
def remove_managed_club_member(
    user_id: UUID, db: DbSession, coordinator: CoordinatorUser
) -> Response:
    club = _assigned_club(db, coordinator)
    membership = db.scalar(
        select(ClubMembership)
        .where(
            ClubMembership.club_id == club.id,
            ClubMembership.student_id == user_id,
            ClubMembership.ended_at.is_(None),
        )
        .with_for_update()
    )
    if membership is None:
        raise HTTPException(status_code=404, detail="Active member not found")
    membership.ended_at = utc_now()
    db.add(
        AuditLog(
            actor_id=coordinator.id,
            action="membership.removed",
            entity_type="club_membership",
            entity_id=str(membership.id),
        )
    )
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/club/join-requests", response_model=list[JoinRequestResponse])
def managed_club_requests(db: DbSession, coordinator: CoordinatorUser):
    club = _assigned_club(db, coordinator)
    rows = db.execute(
        select(ClubJoinRequest, User)
        .join(User, User.id == ClubJoinRequest.student_id)
        .where(ClubJoinRequest.club_id == club.id)
        .order_by(
            (ClubJoinRequest.status == JoinRequestStatus.PENDING).desc(),
            ClubJoinRequest.created_at.desc(),
        )
    ).all()
    return [
        JoinRequestResponse(
            id=request.id,
            club_id=club.id,
            club_name=club.name,
            student_id=str(student.id),
            student_name=student.full_name,
            student_email=student.email,
            reason=request.reason,
            skills=request.skills,
            experience=request.experience,
            status=request.status,
            created_at=request.created_at,
            decided_at=request.decided_at,
        )
        for request, student in rows
    ]


def _decide_managed_request(
    request_id: int,
    data: DecisionRequest,
    db,
    coordinator: User,
    decision: JoinRequestStatus,
) -> JoinRequestResponse:
    request = db.get(ClubJoinRequest, request_id)
    if request is None:
        raise HTTPException(status_code=404, detail="Join request not found")
    club = _require_club_assignment(db, coordinator, request.club_id)
    decided = club_service.decide_join_request(
        db, coordinator, request_id, decision, data.note
    )
    student = db.get(User, decided.student_id)
    if student is None:
        raise HTTPException(status_code=409, detail="Applicant no longer exists")
    return JoinRequestResponse(
        id=decided.id,
        club_id=club.id,
        club_name=club.name,
        student_id=str(student.id),
        student_name=student.full_name,
        student_email=student.email,
        reason=decided.reason,
        skills=decided.skills,
        experience=decided.experience,
        status=decided.status,
        created_at=decided.created_at,
        decided_at=decided.decided_at,
    )


@router.post(
    "/club/join-requests/{request_id}/approve",
    response_model=JoinRequestResponse,
)
def approve_managed_request(
    request_id: int, data: DecisionRequest, db: DbSession, coordinator: CoordinatorUser
):
    return _decide_managed_request(
        request_id, data, db, coordinator, JoinRequestStatus.APPROVED
    )


@router.post(
    "/club/join-requests/{request_id}/reject",
    response_model=JoinRequestResponse,
)
def reject_managed_request(
    request_id: int, data: DecisionRequest, db: DbSession, coordinator: CoordinatorUser
):
    return _decide_managed_request(
        request_id, data, db, coordinator, JoinRequestStatus.REJECTED
    )


@router.patch("/club", response_model=ManagedClubResponse)
def update_managed_club(
    data: ManagedClubUpdate, db: DbSession, coordinator: CoordinatorUser
):
    club = _assigned_club(db, coordinator)
    values = data.model_dump(exclude_unset=True)
    for field, value in values.items():
        if isinstance(value, str):
            value = value.strip() or None
        if field == "name" and value is None:
            raise HTTPException(status_code=422, detail="Club name cannot be blank")
        setattr(club, field, value)
    db.add(
        AuditLog(
            actor_id=coordinator.id,
            action="club.updated",
            entity_type="club",
            entity_id=str(club.id),
        )
    )
    try:
        db.commit()
    except IntegrityError as error:
        db.rollback()
        raise HTTPException(status_code=409, detail="Club name is already in use") from error
    db.refresh(club)
    return _managed_club_response(db, club)


@router.get("/club/events")
def list_managed_events(db: DbSession, coordinator: CoordinatorUser):
    club = _assigned_club(db, coordinator)
    return event_service.list_coordinator_events(db, coordinator, club.id)


@router.post("/club/events", status_code=status.HTTP_201_CREATED)
def create_managed_event(
    data: EventCreate, db: DbSession, coordinator: CoordinatorUser
):
    club = _assigned_club(db, coordinator)
    return event_service.create_event(db, coordinator, club.id, data)


@router.patch("/club/events/{event_id}")
def update_managed_event(
    event_id: int, data: EventUpdate, db: DbSession, coordinator: CoordinatorUser
):
    event = db.get(ClubEvent, event_id)
    if event is None:
        raise HTTPException(status_code=404, detail="Event not found")
    _require_club_assignment(db, coordinator, event.club_id)
    return event_service.update_event(db, coordinator, event_id, data)


@router.post("/club/events/{event_id}/cancel")
def cancel_managed_event(event_id: int, db: DbSession, coordinator: CoordinatorUser):
    event = db.get(ClubEvent, event_id)
    if event is None:
        raise HTTPException(status_code=404, detail="Event not found")
    _require_club_assignment(db, coordinator, event.club_id)
    return event_service.cancel_event(db, coordinator, event_id)


@router.get("/club/events/{event_id}/registrations")
def list_managed_event_registrations(
    event_id: int, db: DbSession, coordinator: CoordinatorUser
):
    event = db.get(ClubEvent, event_id)
    if event is None:
        raise HTTPException(status_code=404, detail="Event not found")
    _require_club_assignment(db, coordinator, event.club_id)
    return event_service.list_event_participants(db, coordinator, event_id)


@router.post("/club/events/{event_id}/attendance/check-in")
def check_in_managed_event_attendee(
    event_id: int,
    data: dict[str, str],
    db: DbSession,
    coordinator: CoordinatorUser,
):
    event = db.get(ClubEvent, event_id)
    if event is None:
        raise HTTPException(status_code=404, detail="Event not found")
    _require_club_assignment(db, coordinator, event.club_id)
    ticket_token = data.get("ticket_token")
    if not ticket_token:
        raise HTTPException(status_code=422, detail="ticket_token is required")
    return event_service.check_in_with_ticket(
        db, coordinator, event_id, ticket_token
    )


@router.post(
    "/club/announcements",
    response_model=AnnouncementResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_managed_announcement(
    data: AnnouncementCreate, db: DbSession, coordinator: CoordinatorUser
):
    club = _assigned_club(db, coordinator)
    return announcement_service.create_announcement(
        db, coordinator, data, club_id=club.id
    )


class CoordinatorClubSummary(BaseModel):
    club_id: int
    club_name: str
    category: str | None
    active_members: int
    pending_join_requests: int
    events: int
    active_event_registrations: int


class CoordinatorDashboardResponse(BaseModel):
    assigned_clubs: list[CoordinatorClubSummary]
    active_members: int
    pending_join_requests: int
    events: int
    active_event_registrations: int


@router.get("/dashboard", response_model=CoordinatorDashboardResponse)
def coordinator_dashboard(
    db: DbSession, coordinator: CoordinatorUser
) -> CoordinatorDashboardResponse:
    membership_count = (
        select(func.count(ClubMembership.id))
        .where(
            ClubMembership.club_id == Club.id,
            ClubMembership.ended_at.is_(None),
        )
        .scalar_subquery()
    )
    pending_request_count = (
        select(func.count(ClubJoinRequest.id))
        .where(
            ClubJoinRequest.club_id == Club.id,
            ClubJoinRequest.status == JoinRequestStatus.PENDING,
        )
        .scalar_subquery()
    )
    event_count = (
        select(func.count(ClubEvent.id))
        .where(ClubEvent.club_id == Club.id)
        .scalar_subquery()
    )
    registration_count = (
        select(func.count(EventRegistration.id))
        .join(ClubEvent, ClubEvent.id == EventRegistration.event_id)
        .where(
            ClubEvent.club_id == Club.id,
            EventRegistration.status == EventRegistrationStatus.REGISTERED,
        )
        .scalar_subquery()
    )
    rows = db.execute(
        select(
            Club.id,
            Club.name,
            Club.category,
            membership_count.label("active_members"),
            pending_request_count.label("pending_join_requests"),
            event_count.label("events"),
            registration_count.label("active_event_registrations"),
        )
        .join(ClubCoordinator, ClubCoordinator.club_id == Club.id)
        .where(
            ClubCoordinator.user_id == coordinator.id,
            ClubCoordinator.revoked_at.is_(None),
            Club.is_active.is_(True),
        )
        .order_by(Club.name)
    ).all()

    assigned_clubs = [
        CoordinatorClubSummary(
            club_id=row.id,
            club_name=row.name,
            category=row.category,
            active_members=row.active_members,
            pending_join_requests=row.pending_join_requests,
            events=row.events,
            active_event_registrations=row.active_event_registrations,
        )
        for row in rows
    ]
    return CoordinatorDashboardResponse(
        assigned_clubs=assigned_clubs,
        active_members=sum(club.active_members for club in assigned_clubs),
        pending_join_requests=sum(
            club.pending_join_requests for club in assigned_clubs
        ),
        events=sum(club.events for club in assigned_clubs),
        active_event_registrations=sum(
            club.active_event_registrations for club in assigned_clubs
        ),
    )
