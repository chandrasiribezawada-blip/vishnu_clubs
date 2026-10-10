from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.entities import (
    Club,
    ClubCoordinator,
    ClubFollower,
    ClubJoinRequest,
    ClubMembership,
    JoinRequestDecision,
    JoinRequestStatus,
    Notification,
    User,
    UserRole,
    AuditLog,
    utc_now,
)


def list_clubs(db: Session) -> list[dict[str, object]]:
    rows = db.execute(
        select(
            Club,
            func.count(func.distinct(ClubMembership.id)).label("member_count"),
            func.count(func.distinct(ClubFollower.id)).label("follower_count"),
        )
        .outerjoin(
            ClubMembership,
            (ClubMembership.club_id == Club.id) & ClubMembership.ended_at.is_(None),
        )
        .outerjoin(ClubFollower, ClubFollower.club_id == Club.id)
        .where(Club.is_active.is_(True))
        .group_by(Club.id)
        .order_by(Club.id)
    ).all()
    return [
        {
            "id": club.id,
            "name": club.name,
            "category": club.category,
            "description": club.description,
            "objectives": club.objectives,
            "contact_email": club.contact_email,
            "member_count": member_count,
            "follower_count": follower_count,
        }
        for club, member_count, follower_count in rows
    ]


def get_club(db: Session, club_id: int) -> Club:
    club = db.get(Club, club_id)
    if club is None or not club.is_active:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Club not found")
    return club


def get_club_response(db: Session, club_id: int) -> dict[str, object]:
    club = get_club(db, club_id)
    member_count = db.scalar(
        select(func.count(ClubMembership.id)).where(
            ClubMembership.club_id == club_id, ClubMembership.ended_at.is_(None)
        )
    )
    follower_count = db.scalar(
        select(func.count(ClubFollower.id)).where(ClubFollower.club_id == club_id)
    )
    return {
        "id": club.id,
        "name": club.name,
        "category": club.category,
        "description": club.description,
        "objectives": club.objectives,
        "contact_email": club.contact_email,
        "member_count": member_count or 0,
        "follower_count": follower_count or 0,
    }


def follow_club(db: Session, student: User, club_id: int) -> None:
    get_club(db, club_id)
    existing = db.scalar(
        select(ClubFollower).where(
            ClubFollower.student_id == student.id, ClubFollower.club_id == club_id
        )
    )
    if existing is None:
        db.add(ClubFollower(student_id=student.id, club_id=club_id))
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            duplicate = db.scalar(
                select(ClubFollower).where(
                    ClubFollower.student_id == student.id,
                    ClubFollower.club_id == club_id,
                )
            )
            if duplicate is None:
                raise


def unfollow_club(db: Session, student: User, club_id: int) -> None:
    get_club(db, club_id)
    existing = db.scalar(
        select(ClubFollower).where(
            ClubFollower.student_id == student.id, ClubFollower.club_id == club_id
        )
    )
    if existing is not None:
        db.delete(existing)
        db.commit()


def list_followed_clubs(db: Session, student: User) -> list[dict[str, object]]:
    followed_ids = set(
        db.scalars(
            select(ClubFollower.club_id).where(
                ClubFollower.student_id == student.id
            )
        ).all()
    )
    return [
        club
        for club in list_clubs(db)
        if club["id"] in followed_ids
    ]


def list_coordinator_clubs(db: Session, coordinator: User) -> list[Club]:
    return list(
        db.scalars(
            select(Club)
            .join(ClubCoordinator, ClubCoordinator.club_id == Club.id)
            .where(
                ClubCoordinator.user_id == coordinator.id,
                ClubCoordinator.revoked_at.is_(None),
                Club.is_active.is_(True),
            )
            .order_by(Club.name)
        ).all()
    )


def submit_join_request(
    db: Session,
    student: User,
    club_id: int,
    reason: str,
    skills: str,
    experience: str | None,
) -> ClubJoinRequest:
    club = get_club(db, club_id)
    pending = db.scalar(
        select(ClubJoinRequest).where(
            ClubJoinRequest.student_id == student.id,
            ClubJoinRequest.club_id == club_id,
            ClubJoinRequest.status == JoinRequestStatus.PENDING,
        )
    )
    active_membership = db.scalar(
        select(ClubMembership).where(
            ClubMembership.student_id == student.id,
            ClubMembership.club_id == club_id,
            ClubMembership.ended_at.is_(None),
        )
    )
    if pending is not None or active_membership is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A pending request or active membership already exists",
        )

    request = ClubJoinRequest(
        student_id=student.id,
        club_id=club.id,
        reason=reason.strip(),
        skills=skills.strip(),
        experience=experience.strip() if experience and experience.strip() else None,
    )
    db.add(request)
    try:
        db.flush()
        db.add(
            Notification(
                recipient_id=student.id,
                title="Membership request submitted",
                message=f"Your request to join {club.name} is pending review.",
                target_path=f"/club/{club.id}",
            )
        )
        db.add(
            AuditLog(
                actor_id=student.id,
                action="membership.requested",
                entity_type="club_join_request",
                entity_id=str(request.id),
            )
        )
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A pending request or active membership already exists",
        ) from exc
    db.refresh(request)
    return request


def list_student_requests(db: Session, student: User) -> list[tuple[ClubJoinRequest, Club]]:
    return list(
        db.execute(
            select(ClubJoinRequest, Club)
            .join(Club, Club.id == ClubJoinRequest.club_id)
            .where(ClubJoinRequest.student_id == student.id)
            .order_by(ClubJoinRequest.created_at.desc())
        ).all()
    )


def list_student_memberships(db: Session, student: User) -> list[tuple[ClubMembership, Club]]:
    return list(
        db.execute(
            select(ClubMembership, Club)
            .join(Club, Club.id == ClubMembership.club_id)
            .where(
                ClubMembership.student_id == student.id,
                ClubMembership.ended_at.is_(None),
            )
            .order_by(ClubMembership.created_at.desc())
        ).all()
    )


def _require_assigned_coordinator(db: Session, coordinator: User, club_id: int) -> None:
    assignment = db.scalar(
        select(ClubCoordinator.id).where(
            ClubCoordinator.user_id == coordinator.id,
            ClubCoordinator.club_id == club_id,
            ClubCoordinator.revoked_at.is_(None),
        )
    )
    if coordinator.role != UserRole.CLUB_ADMIN and assignment is None:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Club access denied")


def list_club_requests(
    db: Session, coordinator: User, club_id: int
) -> list[tuple[ClubJoinRequest, Club, User]]:
    get_club(db, club_id)
    _require_assigned_coordinator(db, coordinator, club_id)
    return list(
        db.execute(
            select(ClubJoinRequest, Club, User)
            .join(Club, Club.id == ClubJoinRequest.club_id)
            .join(User, User.id == ClubJoinRequest.student_id)
            .where(
                ClubJoinRequest.club_id == club_id,
                ClubJoinRequest.status == JoinRequestStatus.PENDING,
            )
            .order_by(ClubJoinRequest.created_at)
        ).all()
    )


def decide_join_request(
    db: Session,
    coordinator: User,
    request_id: int,
    decision: JoinRequestStatus,
    note: str | None,
) -> ClubJoinRequest:
    request = db.get(ClubJoinRequest, request_id, with_for_update=True)
    if request is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Join request not found"
        )
    _require_assigned_coordinator(db, coordinator, request.club_id)
    if request.status != JoinRequestStatus.PENDING:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This request has already been decided",
        )

    club = get_club(db, request.club_id)
    student = db.get(User, request.student_id)
    if student is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Applicant no longer exists"
        )
    request.status = decision
    request.decided_at = utc_now()
    db.add(
        JoinRequestDecision(
            request_id=request.id,
            decided_by=coordinator.id,
            status=decision,
            note=note.strip() if note and note.strip() else None,
        )
    )
    if decision == JoinRequestStatus.APPROVED:
        db.add(
            ClubMembership(
                student_id=request.student_id,
                club_id=request.club_id,
                join_request_id=request.id,
            )
        )
    result = "approved" if decision == JoinRequestStatus.APPROVED else "rejected"
    db.add(
        Notification(
            recipient_id=request.student_id,
            title=f"Membership request {result}",
            message=f"Your request to join {club.name} was {result}.",
            target_path=f"/club/{club.id}",
        )
    )
    db.add(
        AuditLog(
            actor_id=coordinator.id,
            action=f"membership.{result}",
            entity_type="club_join_request",
            entity_id=str(request.id),
        )
    )
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This request has already been decided or a membership already exists",
        ) from exc
    except Exception:
        db.rollback()
        raise
    db.refresh(request)
    return request


def assign_coordinator(db: Session, admin: User, club_id: int, user_id) -> None:
    get_club(db, club_id)
    user = db.get(User, user_id)
    if user is None or not user.is_active:
        raise HTTPException(status_code=404, detail="User not found")
    if user.role == UserRole.CLUB_ADMIN:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Administrators cannot be assigned as club coordinators",
        )
    user.role = UserRole.CLUB_MEMBER_COORDINATOR
    db.add(ClubCoordinator(user_id=user.id, club_id=club_id))
    db.add(
        AuditLog(
            actor_id=admin.id,
            action="coordinator.assigned",
            entity_type="club",
            entity_id=str(club_id),
        )
    )
    try:
        db.commit()
    except Exception as exc:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Coordinator is already assigned to this club",
        ) from exc


def revoke_coordinator(db: Session, admin: User, club_id: int, user_id) -> None:
    assignment = db.scalar(
        select(ClubCoordinator)
        .where(
            ClubCoordinator.user_id == user_id,
            ClubCoordinator.club_id == club_id,
            ClubCoordinator.revoked_at.is_(None),
        )
        .with_for_update()
    )
    if assignment is None:
        raise HTTPException(status_code=404, detail="Active coordinator assignment not found")
    assignment.revoked_at = utc_now()
    has_other_assignments = db.scalar(
        select(ClubCoordinator.id).where(
            ClubCoordinator.user_id == user_id,
            ClubCoordinator.club_id != club_id,
            ClubCoordinator.revoked_at.is_(None),
        )
    )
    user = db.get(User, user_id)
    if user is not None and not has_other_assignments:
        user.role = UserRole.STUDENT
    db.add(
        AuditLog(
            actor_id=admin.id,
            action="coordinator.revoked",
            entity_type="club",
            entity_id=str(club_id),
        )
    )
    db.commit()
