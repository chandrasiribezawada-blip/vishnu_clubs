import hashlib
import secrets
from datetime import UTC, datetime
from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.entities import (
    AuditLog,
    Club,
    ClubCoordinator,
    ClubEvent,
    EventAttendance,
    EventRegistration,
    EventRegistrationStatus,
    EventStatus,
    EventTicket,
    Notification,
    User,
    UserRole,
)
from app.schemas.events import EventCreate, EventUpdate


def _now() -> datetime:
    return datetime.now(UTC)


def _utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


def _get_event(db: Session, event_id: int, *, lock: bool = False) -> ClubEvent:
    statement = select(ClubEvent).where(ClubEvent.id == event_id)
    if lock:
        statement = statement.with_for_update()
    event = db.scalar(statement)
    if event is None:
        raise HTTPException(status_code=404, detail="Event not found")
    return event


def _require_club_access(db: Session, actor: User, club_id: int) -> None:
    if actor.role == UserRole.CLUB_ADMIN:
        return
    assignment = db.scalar(
        select(ClubCoordinator.id).where(
            ClubCoordinator.user_id == actor.id,
            ClubCoordinator.club_id == club_id,
            ClubCoordinator.revoked_at.is_(None),
        )
    )
    if assignment is None:
        raise HTTPException(status_code=403, detail="Club access denied")


def _validate_times(event: ClubEvent) -> None:
    event.start_at = _utc(event.start_at)
    event.end_at = _utc(event.end_at)
    event.registration_opens_at = _utc(event.registration_opens_at)
    event.registration_closes_at = _utc(event.registration_closes_at)
    if event.end_at <= event.start_at:
        raise HTTPException(status_code=422, detail="Event end time must follow start time")
    if event.registration_closes_at < event.registration_opens_at:
        raise HTTPException(
            status_code=422,
            detail="Registration close time must follow its open time",
        )
    if event.registration_closes_at > event.start_at:
        raise HTTPException(
            status_code=422,
            detail="Registration must close by the event start time",
        )


def _response(db: Session, event: ClubEvent) -> dict[str, object]:
    club_name = db.scalar(select(Club.name).where(Club.id == event.club_id))
    registration_count = db.scalar(
        select(func.count(EventRegistration.id)).where(
            EventRegistration.event_id == event.id,
            EventRegistration.status == EventRegistrationStatus.REGISTERED,
        )
    )
    return {
        "id": event.id,
        "club_id": event.club_id,
        "club_name": club_name or "",
        "title": event.title,
        "description": event.description,
        "category": event.category,
        "eligibility": event.eligibility,
        "poster_url": event.poster_url,
        "start_at": _utc(event.start_at),
        "end_at": _utc(event.end_at),
        "registration_opens_at": _utc(event.registration_opens_at),
        "registration_closes_at": _utc(event.registration_closes_at),
        "venue": event.venue,
        "latitude": event.latitude,
        "longitude": event.longitude,
        "capacity": event.capacity,
        "registration_count": registration_count or 0,
        "status": event.status,
        "created_at": _utc(event.created_at),
        "updated_at": _utc(event.updated_at),
    }


def list_published_events(
    db: Session, *, include_past: bool = False
) -> list[dict[str, object]]:
    statement = select(ClubEvent).where(
        ClubEvent.status == EventStatus.PUBLISHED
    )
    if not include_past:
        statement = statement.where(ClubEvent.end_at >= _now())
    events = db.scalars(
        statement.order_by(ClubEvent.start_at, ClubEvent.id)
    ).all()
    return [_response(db, event) for event in events]


def get_event_response(db: Session, event_id: int) -> dict[str, object]:
    event = _get_event(db, event_id)
    if event.status != EventStatus.PUBLISHED:
        raise HTTPException(status_code=404, detail="Event not found")
    return _response(db, event)


def list_coordinator_events(
    db: Session, actor: User, club_id: int
) -> list[dict[str, object]]:
    _require_club_access(db, actor, club_id)
    return [
        _response(db, event)
        for event in db.scalars(
            select(ClubEvent)
            .where(ClubEvent.club_id == club_id)
            .order_by(ClubEvent.start_at.desc())
        ).all()
    ]


def create_event(
    db: Session, actor: User, club_id: int, data: EventCreate
) -> dict[str, object]:
    club = db.get(Club, club_id)
    if club is None or not club.is_active:
        raise HTTPException(status_code=404, detail="Club not found")
    _require_club_access(db, actor, club_id)
    values = data.model_dump()
    values["title"] = values["title"].strip()
    values["venue"] = values["venue"].strip()
    values["description"] = (
        values["description"].strip() if values["description"] else None
    )
    values["category"] = values["category"].strip() if values["category"] else None
    values["poster_url"] = str(values["poster_url"]) if values["poster_url"] else None
    for field in (
        "start_at",
        "end_at",
        "registration_opens_at",
        "registration_closes_at",
    ):
        values[field] = _utc(values[field])
    event = ClubEvent(club_id=club_id, created_by=actor.id, **values)
    _validate_times(event)
    db.add(event)
    db.flush()
    db.add(
        AuditLog(
            actor_id=actor.id,
            action="event.created",
            entity_type="event",
            entity_id=str(event.id),
        )
    )
    db.commit()
    db.refresh(event)
    return _response(db, event)


def update_event(
    db: Session, actor: User, event_id: int, data: EventUpdate
) -> dict[str, object]:
    event = _get_event(db, event_id, lock=True)
    _require_club_access(db, actor, event.club_id)
    if event.status not in (EventStatus.DRAFT, EventStatus.PUBLISHED):
        raise HTTPException(status_code=409, detail="This event can no longer be edited")
    if _utc(event.start_at) <= _now():
        raise HTTPException(status_code=409, detail="A started event can no longer be edited")

    fields = data.model_dump(exclude_unset=True)
    for field, value in fields.items():
        if field in {
            "start_at",
            "end_at",
            "registration_opens_at",
            "registration_closes_at",
        } and value is not None:
            value = _utc(value)
        elif field == "poster_url":
            value = str(value) if value else None
        elif field in {"title", "venue"} and value is not None:
            value = value.strip()
        elif field in {"description", "category"} and value is not None:
            value = value.strip() or None
        setattr(event, field, value)
    if (event.latitude is None) != (event.longitude is None):
        raise HTTPException(
            status_code=422,
            detail="Latitude and longitude must be provided together",
        )
    if event.capacity < (
        db.scalar(
            select(func.count(EventRegistration.id)).where(
                EventRegistration.event_id == event.id,
                EventRegistration.status == EventRegistrationStatus.REGISTERED,
            )
        )
        or 0
    ):
        raise HTTPException(
            status_code=409,
            detail="Capacity cannot be lower than the active registration count",
        )
    _validate_times(event)
    db.add(
        AuditLog(
            actor_id=actor.id,
            action="event.updated",
            entity_type="event",
            entity_id=str(event.id),
        )
    )
    db.commit()
    db.refresh(event)
    return _response(db, event)


def publish_event(db: Session, actor: User, event_id: int) -> dict[str, object]:
    event = _get_event(db, event_id, lock=True)
    _require_club_access(db, actor, event.club_id)
    if event.status != EventStatus.DRAFT:
        raise HTTPException(status_code=409, detail="Only draft events can be published")
    if _utc(event.start_at) <= _now():
        raise HTTPException(status_code=409, detail="An event must start in the future")
    event.status = EventStatus.PUBLISHED
    db.add(
        AuditLog(
            actor_id=actor.id,
            action="event.published",
            entity_type="event",
            entity_id=str(event.id),
        )
    )
    db.commit()
    db.refresh(event)
    return _response(db, event)


def cancel_event(db: Session, actor: User, event_id: int) -> dict[str, object]:
    event = _get_event(db, event_id, lock=True)
    _require_club_access(db, actor, event.club_id)
    if event.status not in (EventStatus.DRAFT, EventStatus.PUBLISHED):
        raise HTTPException(status_code=409, detail="This event cannot be cancelled")
    if _utc(event.start_at) <= _now():
        raise HTTPException(status_code=409, detail="A started event cannot be cancelled")
    event.status = EventStatus.CANCELLED
    registrations = db.scalars(
        select(EventRegistration).where(
            EventRegistration.event_id == event.id,
            EventRegistration.status == EventRegistrationStatus.REGISTERED,
        )
    ).all()
    club_name = db.scalar(select(Club.name).where(Club.id == event.club_id)) or ""
    for registration in registrations:
        registration.status = EventRegistrationStatus.CANCELLED
        registration.cancelled_at = _now()
        ticket = db.scalar(
            select(EventTicket).where(EventTicket.registration_id == registration.id)
        )
        if ticket is not None:
            ticket.revoked_at = _now()
    db.add_all(
        Notification(
            recipient_id=registration.student_id,
            title="Event cancelled",
            message=f"{club_name} cancelled {event.title}.",
        )
        for registration in registrations
    )
    db.add(
        AuditLog(
            actor_id=actor.id,
            action="event.cancelled",
            entity_type="event",
            entity_id=str(event.id),
        )
    )
    db.commit()
    db.refresh(event)
    return _response(db, event)


def register_student(db: Session, student: User, event_id: int) -> dict[str, object]:
    event = _get_event(db, event_id, lock=True)
    now = _now()
    opens_at = _utc(event.registration_opens_at)
    closes_at = _utc(event.registration_closes_at)
    if event.status != EventStatus.PUBLISHED:
        raise HTTPException(status_code=409, detail="Event registration is unavailable")
    if now < opens_at or now > closes_at:
        raise HTTPException(status_code=409, detail="Registration is outside its open window")
    existing = db.scalar(
        select(EventRegistration)
        .where(
            EventRegistration.event_id == event.id,
            EventRegistration.student_id == student.id,
        )
        .with_for_update()
    )
    if existing and existing.status == EventRegistrationStatus.REGISTERED:
        raise HTTPException(status_code=409, detail="You are already registered")
    active_count = db.scalar(
        select(func.count(EventRegistration.id)).where(
            EventRegistration.event_id == event.id,
            EventRegistration.status == EventRegistrationStatus.REGISTERED,
        )
    )
    if (active_count or 0) >= event.capacity:
        raise HTTPException(status_code=409, detail="Event is at capacity")

    if existing:
        existing.status = EventRegistrationStatus.REGISTERED
        existing.registered_at = now
        existing.cancelled_at = None
        registration = existing
    else:
        registration = EventRegistration(
            event_id=event.id,
            student_id=student.id,
            status=EventRegistrationStatus.REGISTERED,
        )
        db.add(registration)
    db.flush()
    db.add(
        Notification(
            recipient_id=student.id,
            title="Event registration confirmed",
            message=f"You are registered for {event.title}.",
            target_path=f"/events/{event.id}",
        )
    )
    db.add(
        AuditLog(
            actor_id=student.id,
            action="event.registration.created",
            entity_type="event_registration",
            entity_id=str(registration.id),
        )
    )
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(status_code=409, detail="You are already registered") from exc
    db.refresh(registration)
    return {
        "id": registration.id,
        "event_id": registration.event_id,
        "status": registration.status,
        "registered_at": registration.registered_at,
        "cancelled_at": registration.cancelled_at,
    }


def cancel_registration(
    db: Session, student: User, event_id: int
) -> dict[str, object]:
    event = _get_event(db, event_id, lock=True)
    if _utc(event.start_at) <= _now():
        raise HTTPException(status_code=409, detail="Registration can no longer be cancelled")
    registration = db.scalar(
        select(EventRegistration)
        .where(
            EventRegistration.event_id == event.id,
            EventRegistration.student_id == student.id,
        )
        .with_for_update()
    )
    if registration is None or registration.status != EventRegistrationStatus.REGISTERED:
        raise HTTPException(status_code=404, detail="Active registration not found")
    registration.status = EventRegistrationStatus.CANCELLED
    registration.cancelled_at = _now()
    ticket = db.scalar(
        select(EventTicket)
        .where(EventTicket.registration_id == registration.id)
        .with_for_update()
    )
    if ticket is not None:
        ticket.revoked_at = _now()
    db.add(
        AuditLog(
            actor_id=student.id,
            action="event.registration.cancelled",
            entity_type="event_registration",
            entity_id=str(registration.id),
        )
    )
    db.commit()
    db.refresh(registration)
    return {
        "id": registration.id,
        "event_id": registration.event_id,
        "status": registration.status,
        "registered_at": registration.registered_at,
        "cancelled_at": registration.cancelled_at,
    }


def list_student_events(db: Session, student: User) -> list[dict[str, object]]:
    rows = db.execute(
        select(EventRegistration, ClubEvent, EventAttendance.id)
        .join(ClubEvent, ClubEvent.id == EventRegistration.event_id)
        .outerjoin(
            EventAttendance,
            EventAttendance.registration_id == EventRegistration.id,
        )
        .where(EventRegistration.student_id == student.id)
        .order_by(ClubEvent.start_at.desc(), EventRegistration.registered_at.desc())
    ).all()
    result = []
    for registration, event, attendance_id in rows:
        result.append(
            {
                **_response(db, event),
                "registration_id": registration.id,
                "registration_status": registration.status,
                "registered_at": registration.registered_at,
                "cancelled_at": registration.cancelled_at,
                "attended": attendance_id is not None,
            }
        )
    return result


def list_event_participants(
    db: Session, actor: User, event_id: int
) -> list[dict[str, object]]:
    event = _get_event(db, event_id)
    _require_club_access(db, actor, event.club_id)
    rows = db.execute(
        select(EventRegistration, User, EventAttendance.id)
        .join(User, User.id == EventRegistration.student_id)
        .outerjoin(
            EventAttendance,
            EventAttendance.registration_id == EventRegistration.id,
        )
        .where(
            EventRegistration.event_id == event.id,
            EventRegistration.status == EventRegistrationStatus.REGISTERED,
        )
        .order_by(EventRegistration.registered_at)
    ).all()
    return [
        {
            "registration_id": registration.id,
            "student_name": user.full_name,
            "student_email": user.email,
            "registered_at": registration.registered_at,
            "attended": attendance_id is not None,
        }
        for registration, user, attendance_id in rows
    ]


def get_event_attendance_summary(
    db: Session, actor: User, event_id: int
) -> dict[str, object]:
    event = _get_event(db, event_id)
    _require_club_access(db, actor, event.club_id)
    registered = db.scalar(
        select(func.count(EventRegistration.id)).where(
            EventRegistration.event_id == event.id,
            EventRegistration.status == EventRegistrationStatus.REGISTERED,
        )
    ) or 0
    attended = db.scalar(
        select(func.count(EventAttendance.id)).where(
            EventAttendance.event_id == event.id
        )
    ) or 0
    return {
        "event_id": event.id,
        "registered_count": registered,
        "attended_count": attended,
        "not_attended_count": registered - attended,
    }


def issue_event_ticket(
    db: Session, student: User, event_id: int
) -> dict[str, object]:
    event = _get_event(db, event_id, lock=True)
    if event.status != EventStatus.PUBLISHED or _utc(event.end_at) <= _now():
        raise HTTPException(status_code=409, detail="An event pass is not available")
    registration = db.scalar(
        select(EventRegistration)
        .where(
            EventRegistration.event_id == event.id,
            EventRegistration.student_id == student.id,
            EventRegistration.status == EventRegistrationStatus.REGISTERED,
        )
        .with_for_update()
    )
    if registration is None:
        raise HTTPException(status_code=403, detail="An active event registration is required")

    token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
    ticket = db.scalar(
        select(EventTicket)
        .where(EventTicket.registration_id == registration.id)
        .with_for_update()
    )
    if ticket is not None and ticket.consumed_at is not None:
        raise HTTPException(status_code=409, detail="Attendance has already been recorded")
    now = _now()
    if ticket is None:
        ticket = EventTicket(
            registration_id=registration.id,
            token_hash=token_hash,
            expires_at=_utc(event.end_at),
        )
        db.add(ticket)
    else:
        ticket.token_hash = token_hash
        ticket.issued_at = now
        ticket.expires_at = _utc(event.end_at)
        ticket.revoked_at = None
        ticket.consumed_at = None
    db.add(
        AuditLog(
            actor_id=student.id,
            action="event.ticket.issued",
            entity_type="event_registration",
            entity_id=str(registration.id),
        )
    )
    db.commit()
    db.refresh(ticket)
    return {"ticket_token": token, "expires_at": _utc(ticket.expires_at)}


def check_in_with_ticket(
    db: Session, actor: User, event_id: int, token: str
) -> dict[str, object]:
    event = _get_event(db, event_id, lock=True)
    _require_club_access(db, actor, event.club_id)
    now = _now()
    if event.status != EventStatus.PUBLISHED:
        raise HTTPException(status_code=409, detail="Attendance is not open for this event")
    if _utc(event.start_at) > now or _utc(event.end_at) < now:
        raise HTTPException(status_code=409, detail="Attendance is outside the event time")
    token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
    ticket = db.scalar(
        select(EventTicket)
        .where(EventTicket.token_hash == token_hash)
        .with_for_update()
    )
    if (
        ticket is None
        or ticket.revoked_at is not None
        or ticket.consumed_at is not None
        or _utc(ticket.expires_at) <= now
    ):
        raise HTTPException(
            status_code=409,
            detail="Ticket is invalid, expired, revoked, or already used",
        )
    registration = db.scalar(
        select(EventRegistration)
        .where(EventRegistration.id == ticket.registration_id)
        .with_for_update()
    )
    if (
        registration is None
        or registration.event_id != event.id
        or registration.status != EventRegistrationStatus.REGISTERED
    ):
        raise HTTPException(status_code=409, detail="Ticket registration is not active")
    existing = db.scalar(
        select(EventAttendance.id).where(
            EventAttendance.registration_id == registration.id
        )
    )
    if existing is not None:
        raise HTTPException(status_code=409, detail="Attendance was already recorded")

    ticket.consumed_at = now
    attendance = EventAttendance(
        registration_id=registration.id,
        event_id=event.id,
        student_id=registration.student_id,
        checked_in_by=actor.id,
    )
    db.add(attendance)
    db.add(
        Notification(
            recipient_id=registration.student_id,
            title="Event attendance recorded",
            message=f"Your attendance for {event.title} was recorded.",
            target_path=f"/events/{event.id}",
        )
    )
    db.add(
        AuditLog(
            actor_id=actor.id,
            action="event.attendance.checked_in",
            entity_type="event_attendance",
            entity_id=str(registration.id),
        )
    )
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="Attendance was already recorded",
        ) from exc
    db.refresh(attendance)
    return {
        "event_id": event.id,
        "event_title": event.title,
        "checked_in_at": _utc(attendance.checked_in_at),
        "result": "ATTENDANCE_RECORDED",
    }


def list_student_attendance(db: Session, student: User) -> list[dict[str, object]]:
    rows = db.execute(
        select(EventAttendance, ClubEvent, Club.name)
        .join(ClubEvent, ClubEvent.id == EventAttendance.event_id)
        .join(Club, Club.id == ClubEvent.club_id)
        .where(EventAttendance.student_id == student.id)
        .order_by(EventAttendance.checked_in_at.desc())
    ).all()
    return [
        {
            "event_id": event.id,
            "event_title": event.title,
            "club_name": club_name,
            "checked_in_at": _utc(attendance.checked_in_at),
        }
        for attendance, event, club_name in rows
    ]
