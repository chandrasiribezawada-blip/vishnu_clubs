from datetime import datetime

from fastapi import APIRouter, Query, Response, status
from pydantic import BaseModel

from app.api.dependencies import CoordinatorOrAdmin, DbSession, StudentUser
from app.schemas.events import (
    AttendanceHistoryResponse,
    CheckInRequest,
    CheckInResponse,
    EventCreate,
    EventRegistrationResponse,
    EventResponse,
    EventTicketResponse,
    EventUpdate,
    MyEventResponse,
)
from app.services import event_service

router = APIRouter(tags=["events", "registrations"])


class EventParticipantResponse(BaseModel):
    registration_id: int
    student_name: str
    student_email: str
    registered_at: datetime
    attended: bool


class EventAttendanceSummaryResponse(BaseModel):
    event_id: int
    registered_count: int
    attended_count: int
    not_attended_count: int


@router.get("/events", response_model=list[EventResponse])
def list_events(
    db: DbSession,
    include_past: bool = Query(default=False),
) -> list[dict[str, object]]:
    return event_service.list_published_events(db, include_past=include_past)


@router.get("/events/{event_id}", response_model=EventResponse)
def get_event(event_id: int, db: DbSession) -> dict[str, object]:
    return event_service.get_event_response(db, event_id)


@router.post(
    "/clubs/{club_id}/events",
    response_model=EventResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_event(
    club_id: int,
    data: EventCreate,
    db: DbSession,
    coordinator: CoordinatorOrAdmin,
) -> dict[str, object]:
    return event_service.create_event(db, coordinator, club_id, data)


@router.get(
    "/clubs/{club_id}/events/manage",
    response_model=list[EventResponse],
)
def list_managed_events(
    club_id: int,
    db: DbSession,
    coordinator: CoordinatorOrAdmin,
) -> list[dict[str, object]]:
    return event_service.list_coordinator_events(db, coordinator, club_id)


@router.patch("/events/{event_id}", response_model=EventResponse)
def update_event(
    event_id: int,
    data: EventUpdate,
    db: DbSession,
    coordinator: CoordinatorOrAdmin,
) -> dict[str, object]:
    return event_service.update_event(db, coordinator, event_id, data)


@router.post("/events/{event_id}/publish", response_model=EventResponse)
def publish_event(
    event_id: int,
    db: DbSession,
    coordinator: CoordinatorOrAdmin,
) -> dict[str, object]:
    return event_service.publish_event(db, coordinator, event_id)


@router.post("/events/{event_id}/cancel", response_model=EventResponse)
def cancel_event(
    event_id: int,
    db: DbSession,
    coordinator: CoordinatorOrAdmin,
) -> dict[str, object]:
    return event_service.cancel_event(db, coordinator, event_id)


@router.get(
    "/events/{event_id}/participants",
    response_model=list[EventParticipantResponse],
)
def event_participants(
    event_id: int,
    db: DbSession,
    coordinator: CoordinatorOrAdmin,
) -> list[dict[str, object]]:
    return event_service.list_event_participants(db, coordinator, event_id)


@router.get(
    "/events/{event_id}/attendance/summary",
    response_model=EventAttendanceSummaryResponse,
)
def event_attendance_summary(
    event_id: int,
    db: DbSession,
    coordinator: CoordinatorOrAdmin,
) -> dict[str, object]:
    return event_service.get_event_attendance_summary(db, coordinator, event_id)


@router.post(
    "/events/{event_id}/registrations",
    response_model=EventRegistrationResponse,
    status_code=status.HTTP_201_CREATED,
)
def register_for_event(
    event_id: int,
    db: DbSession,
    student: StudentUser,
) -> dict[str, object]:
    return event_service.register_student(db, student, event_id)


@router.delete(
    "/events/{event_id}/registrations/me",
    response_model=EventRegistrationResponse,
)
def cancel_my_registration(
    event_id: int,
    db: DbSession,
    student: StudentUser,
) -> dict[str, object]:
    return event_service.cancel_registration(db, student, event_id)


@router.get("/me/events", response_model=list[MyEventResponse])
def my_events(db: DbSession, student: StudentUser) -> list[dict[str, object]]:
    return event_service.list_student_events(db, student)


@router.post(
    "/events/{event_id}/pass",
    response_model=EventTicketResponse,
    status_code=status.HTTP_201_CREATED,
)
def issue_event_pass(
    event_id: int,
    db: DbSession,
    student: StudentUser,
    response: Response,
) -> dict[str, object]:
    response.headers["Cache-Control"] = "no-store, private"
    return event_service.issue_event_ticket(db, student, event_id)


@router.post(
    "/events/{event_id}/attendance/check-in",
    response_model=CheckInResponse,
)
def check_in_attendee(
    event_id: int,
    data: CheckInRequest,
    db: DbSession,
    coordinator: CoordinatorOrAdmin,
) -> dict[str, object]:
    return event_service.check_in_with_ticket(
        db,
        coordinator,
        event_id,
        data.ticket_token,
    )


@router.get(
    "/me/attendance",
    response_model=list[AttendanceHistoryResponse],
)
def my_attendance(db: DbSession, student: StudentUser) -> list[dict[str, object]]:
    return event_service.list_student_attendance(db, student)
