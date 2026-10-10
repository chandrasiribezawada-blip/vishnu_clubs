from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy.orm import Session

from app.api.dependencies import (
    CoordinatorOrAdmin,
    CoordinatorUser,
    DbSession,
    StudentUser,
)
from app.models.entities import Club, ClubJoinRequest, JoinRequestStatus, User
from app.schemas.clubs import (
    ClubResponse,
    DecisionRequest,
    JoinRequestCreate,
    JoinRequestResponse,
    MembershipResponse,
)
from app.services import club_service

router = APIRouter(tags=["clubs", "memberships"])


def _join_request_response(
    request: ClubJoinRequest, club: Club, student: User
) -> JoinRequestResponse:
    return JoinRequestResponse(
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


@router.get("/clubs", response_model=list[ClubResponse])
def list_clubs(db: DbSession) -> list[dict[str, object]]:
    return club_service.list_clubs(db)


@router.get("/clubs/{club_id}", response_model=ClubResponse)
def get_club(club_id: int, db: DbSession) -> dict[str, object]:
    return club_service.get_club_response(db, club_id)


@router.post("/clubs/{club_id}/follow", status_code=status.HTTP_204_NO_CONTENT)
def follow_club(club_id: int, db: DbSession, student: StudentUser) -> Response:
    club_service.follow_club(db, student, club_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("/clubs/{club_id}/follow", status_code=status.HTTP_204_NO_CONTENT)
def unfollow_club(club_id: int, db: DbSession, student: StudentUser) -> Response:
    club_service.unfollow_club(db, student, club_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/me/followed-clubs", response_model=list[ClubResponse])
def my_followed_clubs(db: DbSession, student: StudentUser) -> list[dict[str, object]]:
    return club_service.list_followed_clubs(db, student)


@router.get("/me/coordinator-clubs", response_model=list[ClubResponse])
def my_coordinator_clubs(
    db: DbSession, coordinator: CoordinatorUser
) -> list[dict[str, object]]:
    return [
        club_service.get_club_response(db, club.id)
        for club in club_service.list_coordinator_clubs(db, coordinator)
    ]


@router.post(
    "/clubs/{club_id}/join-requests",
    response_model=JoinRequestResponse,
    status_code=status.HTTP_201_CREATED,
)
def submit_join_request(
    club_id: int, data: JoinRequestCreate, db: DbSession, student: StudentUser
) -> JoinRequestResponse:
    request = club_service.submit_join_request(
        db,
        student,
        club_id,
        data.reason,
        data.skills,
        data.experience,
    )
    club = club_service.get_club(db, club_id)
    return _join_request_response(request, club, student)


@router.get("/me/join-requests", response_model=list[JoinRequestResponse])
def my_join_requests(db: DbSession, student: StudentUser) -> list[JoinRequestResponse]:
    return [
        _join_request_response(request, club, student)
        for request, club in club_service.list_student_requests(db, student)
    ]


@router.get("/me/memberships", response_model=list[MembershipResponse])
def my_memberships(db: DbSession, student: StudentUser) -> list[MembershipResponse]:
    return [
        MembershipResponse(
            id=membership.id,
            club_id=club.id,
            club_name=club.name,
            created_at=membership.created_at,
        )
        for membership, club in club_service.list_student_memberships(db, student)
    ]


@router.get(
    "/clubs/{club_id}/join-requests",
    response_model=list[JoinRequestResponse],
)
def club_join_requests(
    club_id: int,
    db: DbSession,
    coordinator: CoordinatorUser,
) -> list[JoinRequestResponse]:
    rows = club_service.list_club_requests(db, coordinator, club_id)
    return [_join_request_response(*row) for row in rows]


def _decision_response(
    request_id: int,
    data: DecisionRequest,
    db: Session,
    coordinator: User,
    decision: JoinRequestStatus,
) -> JoinRequestResponse:
    request = club_service.decide_join_request(
        db, coordinator, request_id, decision, data.note
    )
    club = club_service.get_club(db, request.club_id)
    student = db.get(User, request.student_id)
    if student is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Applicant no longer exists",
        )
    return _join_request_response(request, club, student)


@router.post(
    "/join-requests/{request_id}/approve",
    response_model=JoinRequestResponse,
)
def approve_join_request(
    request_id: int,
    data: DecisionRequest,
    db: DbSession,
    coordinator: CoordinatorOrAdmin,
) -> JoinRequestResponse:
    return _decision_response(
        request_id, data, db, coordinator, JoinRequestStatus.APPROVED
    )


@router.post(
    "/join-requests/{request_id}/reject",
    response_model=JoinRequestResponse,
)
def reject_join_request(
    request_id: int,
    data: DecisionRequest,
    db: DbSession,
    coordinator: CoordinatorOrAdmin,
) -> JoinRequestResponse:
    return _decision_response(
        request_id, data, db, coordinator, JoinRequestStatus.REJECTED
    )
