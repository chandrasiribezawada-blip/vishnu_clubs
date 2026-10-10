from uuid import UUID

from fastapi import APIRouter, HTTPException, Response, status
from pydantic import BaseModel, ConfigDict, EmailStr, Field
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError

from app.api.dependencies import AdminUser, DbSession
from app.core.security import hash_password
from app.models.entities import (
    Announcement,
    AuditLog,
    Club,
    ClubCoordinator,
    ClubEvent,
    ClubJoinRequest,
    EventRegistration,
    EventRegistrationStatus,
    JoinRequestStatus,
    User,
    UserRole,
    utc_now,
)
from app.services import event_service, announcement_service
from app.schemas.announcements import AnnouncementCreate, AnnouncementResponse
from app.services import announcement_service
from app.services import club_service

router = APIRouter(prefix="/admin", tags=["admin"])


class CoordinatorAssignmentRequest(BaseModel):
    user_id: UUID


class CoordinatorCreateRequest(BaseModel):
    email: EmailStr
    full_name: str = Field(min_length=2, max_length=160)
    password: str = Field(min_length=12, max_length=128)
    club_id: int


class AdminClubCreateRequest(BaseModel):
    name: str = Field(min_length=2, max_length=200)
    category: str | None = Field(default=None, max_length=100)
    description: str | None = None
    objectives: str | None = None
    contact_email: EmailStr | None = None


class AdminClubUpdateRequest(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=200)
    category: str | None = Field(default=None, max_length=100)
    description: str | None = None
    objectives: str | None = None
    contact_email: EmailStr | None = None

    model_config = ConfigDict(extra="forbid")


class AdminClubResponse(BaseModel):
    id: int
    name: str
    category: str | None
    description: str | None
    objectives: str | None
    contact_email: str | None
    is_active: bool


class AdminEventResponse(BaseModel):
    id: int
    club_id: int
    club_name: str
    title: str
    description: str | None
    category: str | None
    eligibility: str | None
    poster_url: str | None
    start_at: object
    end_at: object
    registration_opens_at: object
    registration_closes_at: object
    venue: str
    latitude: float | None
    longitude: float | None
    capacity: int
    registration_count: int
    status: object
    created_at: object
    updated_at: object


class AdminDashboardResponse(BaseModel):
    active_clubs: int
    total_students: int
    active_users: int
    total_coordinators: int
    coordinator_assignments: int
    pending_join_requests: int
    events: int
    active_event_registrations: int


class AdminUserResponse(BaseModel):
    id: UUID
    full_name: str
    email: str
    role: UserRole


class CoordinatorAssignmentResponse(BaseModel):
    user_id: UUID
    full_name: str
    email: str
    club_id: int
    club_name: str


@router.get("/dashboard", response_model=AdminDashboardResponse)
def admin_dashboard(db: DbSession, admin: AdminUser) -> dict[str, int]:
    return {
        "active_clubs": db.scalar(
            select(func.count(Club.id)).where(Club.is_active.is_(True))
        )
        or 0,
        "total_students": db.scalar(
            select(func.count(User.id)).where(
                User.is_active.is_(True),
                User.role == UserRole.STUDENT,
            )
        )
        or 0,
        "active_users": db.scalar(
            select(func.count(User.id)).where(User.is_active.is_(True))
        )
        or 0,
        "total_coordinators": db.scalar(
            select(func.count(func.distinct(ClubCoordinator.user_id))).where(
                ClubCoordinator.revoked_at.is_(None)
            )
        )
        or 0,
        "coordinator_assignments": db.scalar(
            select(func.count(ClubCoordinator.id)).where(
                ClubCoordinator.revoked_at.is_(None)
            )
        )
        or 0,
        "pending_join_requests": db.scalar(
            select(func.count(ClubJoinRequest.id)).where(
                ClubJoinRequest.status == JoinRequestStatus.PENDING
            )
        )
        or 0,
        "events": db.scalar(select(func.count(ClubEvent.id))) or 0,
        "active_event_registrations": db.scalar(
            select(func.count(EventRegistration.id)).where(
                EventRegistration.status == EventRegistrationStatus.REGISTERED
            )
        )
        or 0,
    }


@router.get(
    "/announcements",
    response_model=list[AnnouncementResponse],
)
def list_admin_announcements(
    db: DbSession, admin: AdminUser
) -> list[dict[str, object]]:
    rows = db.scalars(
        select(Announcement).order_by(
            Announcement.created_at.desc(), Announcement.id.desc()
        )
    ).all()
    return [
        announcement_service.announcement_response(db, announcement)
        for announcement in rows
    ]


@router.post(
    "/announcements",
    response_model=AnnouncementResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_platform_announcement(
    data: AnnouncementCreate, db: DbSession, admin: AdminUser
) -> dict[str, object]:
    return announcement_service.create_announcement(
        db, admin, data, club_id=None
    )


@router.get("/users", response_model=list[AdminUserResponse])
def list_assignable_users(
    db: DbSession, admin: AdminUser, role: UserRole | None = None
) -> list[User]:
    statement = select(User).where(User.is_active.is_(True))
    if role is not None:
        statement = statement.where(User.role == role)
    return list(db.scalars(statement.order_by(User.full_name, User.email)).all())


@router.get("/clubs", response_model=list[AdminClubResponse])
def list_admin_clubs(db: DbSession, admin: AdminUser) -> list[Club]:
    return list(db.scalars(select(Club).order_by(Club.name)).all())


@router.post(
    "/clubs",
    response_model=AdminClubResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_admin_club(
    data: AdminClubCreateRequest, db: DbSession, admin: AdminUser
) -> Club:
    values = data.model_dump()
    values["name"] = values["name"].strip()
    for field in ("category", "description", "objectives", "contact_email"):
        if values[field] is not None:
            values[field] = str(values[field]).strip() or None
    club = Club(**values)
    db.add(club)
    try:
        db.flush()
        db.add(
            AuditLog(
                actor_id=admin.id,
                action="club.created",
                entity_type="club",
                entity_id=str(club.id),
            )
        )
        db.commit()
    except IntegrityError as error:
        db.rollback()
        raise HTTPException(status_code=409, detail="Club name is already in use") from error
    db.refresh(club)
    return club


@router.patch("/clubs/{club_id}", response_model=AdminClubResponse)
def update_admin_club(
    club_id: int, data: AdminClubUpdateRequest, db: DbSession, admin: AdminUser
) -> Club:
    club = db.get(Club, club_id)
    if club is None:
        raise HTTPException(status_code=404, detail="Club not found")
    for field, value in data.model_dump(exclude_unset=True).items():
        if isinstance(value, str):
            value = value.strip() or None
        if field == "name" and value is None:
            raise HTTPException(status_code=422, detail="Club name cannot be blank")
        setattr(club, field, value)
    db.add(
        AuditLog(
            actor_id=admin.id,
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
    return club


@router.patch("/clubs/{club_id}/activation", response_model=AdminClubResponse)
def set_club_activation(
    club_id: int, active: bool, db: DbSession, admin: AdminUser
) -> Club:
    club = db.get(Club, club_id)
    if club is None:
        raise HTTPException(status_code=404, detail="Club not found")
    club.is_active = active
    db.add(
        AuditLog(
            actor_id=admin.id,
            action="club.activated" if active else "club.deactivated",
            entity_type="club",
            entity_id=str(club.id),
        )
    )
    db.commit()
    db.refresh(club)
    return club


@router.post("/coordinators", response_model=AdminUserResponse, status_code=201)
def create_coordinator(
    data: CoordinatorCreateRequest, db: DbSession, admin: AdminUser
) -> User:
    club = db.get(Club, data.club_id)
    if club is None or not club.is_active:
        raise HTTPException(status_code=404, detail="Active club not found")
    email = str(data.email).lower()
    if db.scalar(select(User.id).where(User.email == email)):
        raise HTTPException(status_code=409, detail="Email is already registered")
    user = User(
        email=email,
        full_name=data.full_name.strip(),
        password_hash=hash_password(data.password),
        role=UserRole.CLUB_MEMBER_COORDINATOR,
    )
    db.add(user)
    try:
        db.flush()
        db.add(ClubCoordinator(user_id=user.id, club_id=club.id))
        db.add(
            AuditLog(
                actor_id=admin.id,
                action="coordinator.created_and_assigned",
                entity_type="club",
                entity_id=str(club.id),
            )
        )
        db.commit()
    except IntegrityError as error:
        db.rollback()
        raise HTTPException(status_code=409, detail="Coordinator account could not be created") from error
    db.refresh(user)
    return user


@router.get("/events", response_model=list[AdminEventResponse])
def list_moderated_events(db: DbSession, admin: AdminUser):
    rows = db.scalars(select(ClubEvent).order_by(ClubEvent.start_at.desc())).all()
    return [event_service._response(db, event) for event in rows]


@router.post("/events/{event_id}/cancel", response_model=AdminEventResponse)
def cancel_moderated_event(event_id: int, db: DbSession, admin: AdminUser):
    event = db.get(ClubEvent, event_id)
    if event is None:
        raise HTTPException(status_code=404, detail="Event not found")
    return event_service.cancel_event(db, admin, event_id)


@router.post("/announcements/{announcement_id}/cancel")
def cancel_moderated_announcement(
    announcement_id: int, db: DbSession, admin: AdminUser
):
    return announcement_service.cancel_announcement(db, admin, announcement_id)


@router.get(
    "/coordinators",
    response_model=list[CoordinatorAssignmentResponse],
)
def list_coordinator_assignments(
    db: DbSession, admin: AdminUser
) -> list[dict[str, object]]:
    rows = db.execute(
        select(ClubCoordinator, User, Club)
        .join(User, User.id == ClubCoordinator.user_id)
        .join(Club, Club.id == ClubCoordinator.club_id)
        .where(ClubCoordinator.revoked_at.is_(None))
        .order_by(Club.name, User.full_name)
    ).all()
    return [
        {
            "user_id": user.id,
            "full_name": user.full_name,
            "email": user.email,
            "club_id": club.id,
            "club_name": club.name,
        }
        for _, user, club in rows
    ]


@router.post(
    "/clubs/{club_id}/coordinators",
    status_code=status.HTTP_204_NO_CONTENT,
)
def assign_coordinator(
    club_id: int,
    data: CoordinatorAssignmentRequest,
    db: DbSession,
    admin: AdminUser,
) -> None:
    club_service.assign_coordinator(db, admin, club_id, data.user_id)


@router.delete(
    "/clubs/{club_id}/coordinators/{user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
def revoke_coordinator(
    club_id: int, user_id: UUID, db: DbSession, admin: AdminUser
) -> None:
    club_service.revoke_coordinator(db, admin, club_id, user_id)
