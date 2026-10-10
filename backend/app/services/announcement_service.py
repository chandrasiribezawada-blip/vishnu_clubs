from datetime import UTC, datetime

from fastapi import HTTPException
from sqlalchemy import select, union
from sqlalchemy.orm import Session

from app.models.entities import (
    Announcement,
    AnnouncementStatus,
    AuditLog,
    Club,
    ClubCoordinator,
    ClubFollower,
    ClubMembership,
    Notification,
    User,
    UserRole,
)
from app.schemas.announcements import AnnouncementCreate, AnnouncementUpdate


def _now() -> datetime:
    return datetime.now(UTC)


def _utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def _club_access(db: Session, actor: User, club_id: int) -> None:
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


def announcement_response(
    db: Session, announcement: Announcement
) -> dict[str, object]:
    club_name = (
        db.scalar(select(Club.name).where(Club.id == announcement.club_id))
        if announcement.club_id is not None
        else None
    )
    return {
        "id": announcement.id,
        "club_id": announcement.club_id,
        "club_name": club_name,
        "title": announcement.title,
        "body": announcement.body,
        "status": announcement.status,
        "published_at": _utc(announcement.published_at),
        "expires_at": _utc(announcement.expires_at),
        "created_at": _utc(announcement.created_at),
        "updated_at": _utc(announcement.updated_at),
    }


def _recipient_ids(db: Session, announcement: Announcement) -> set[object]:
    if announcement.club_id is None:
        return set(
            db.scalars(
                select(User.id).where(
                    User.is_active.is_(True),
                    User.role == UserRole.STUDENT,
                )
            ).all()
        )
    recipients = union(
        select(ClubFollower.student_id).where(
            ClubFollower.club_id == announcement.club_id
        ),
        select(ClubMembership.student_id).where(
            ClubMembership.club_id == announcement.club_id,
            ClubMembership.ended_at.is_(None),
        ),
    )
    return set(
        db.scalars(
            select(User.id)
            .where(
                User.id.in_(recipients),
                User.is_active.is_(True),
                User.role == UserRole.STUDENT,
            )
        ).all()
    )


def _notify_recipients(db: Session, announcement: Announcement) -> None:
    target = "/announcements"
    db.add_all(
        Notification(
            recipient_id=recipient_id,
            title=announcement.title,
            message=announcement.body,
            target_path=target,
        )
        for recipient_id in _recipient_ids(db, announcement)
    )


def create_announcement(
    db: Session,
    actor: User,
    data: AnnouncementCreate,
    *,
    club_id: int | None,
) -> dict[str, object]:
    if club_id is not None:
        club = db.get(Club, club_id)
        if club is None or not club.is_active:
            raise HTTPException(status_code=404, detail="Club not found")
        _club_access(db, actor, club_id)
    elif actor.role != UserRole.CLUB_ADMIN:
        raise HTTPException(status_code=403, detail="Administrator access required")
    if (
        data.publish
        and data.expires_at is not None
        and _utc(data.expires_at) <= _now()
    ):
        raise HTTPException(status_code=422, detail="Announcement expiration is in the past")
    announcement = Announcement(
        club_id=club_id,
        created_by=actor.id,
        title=data.title.strip(),
        body=data.body.strip(),
        status=(
            AnnouncementStatus.PUBLISHED
            if data.publish
            else AnnouncementStatus.DRAFT
        ),
        published_at=_now() if data.publish else None,
        expires_at=_utc(data.expires_at),
    )
    db.add(announcement)
    db.flush()
    if data.publish:
        _notify_recipients(db, announcement)
    db.add(
        AuditLog(
            actor_id=actor.id,
            action="announcement.created",
            entity_type="announcement",
            entity_id=str(announcement.id),
        )
    )
    db.commit()
    db.refresh(announcement)
    return announcement_response(db, announcement)


def list_student_announcements(
    db: Session, actor: User
) -> list[dict[str, object]]:
    now = _now()
    statement = select(Announcement).where(
        Announcement.status == AnnouncementStatus.PUBLISHED,
        Announcement.published_at <= now,
        (Announcement.expires_at.is_(None)) | (Announcement.expires_at > now),
    )
    if actor.role == UserRole.STUDENT:
        relevant_clubs = union(
            select(ClubFollower.club_id).where(ClubFollower.student_id == actor.id),
            select(ClubMembership.club_id).where(
                ClubMembership.student_id == actor.id,
                ClubMembership.ended_at.is_(None),
            ),
        )
        statement = statement.where(
            (Announcement.club_id.is_(None))
            | Announcement.club_id.in_(relevant_clubs)
        )
    elif actor.role == UserRole.CLUB_MEMBER_COORDINATOR:
        assigned_clubs = select(ClubCoordinator.club_id).where(
            ClubCoordinator.user_id == actor.id,
            ClubCoordinator.revoked_at.is_(None),
        )
        statement = statement.where(
            (Announcement.club_id.is_(None))
            | Announcement.club_id.in_(assigned_clubs)
        )
    rows = db.scalars(
        statement.order_by(Announcement.published_at.desc(), Announcement.id.desc())
    ).all()
    return [announcement_response(db, row) for row in rows]


def list_club_announcements(
    db: Session, club_id: int
) -> list[dict[str, object]]:
    club = db.get(Club, club_id)
    if club is None or not club.is_active:
        raise HTTPException(status_code=404, detail="Club not found")
    now = _now()
    rows = db.scalars(
        select(Announcement)
        .where(
            Announcement.club_id == club_id,
            Announcement.status == AnnouncementStatus.PUBLISHED,
            Announcement.published_at <= now,
            (Announcement.expires_at.is_(None))
            | (Announcement.expires_at > now),
        )
        .order_by(Announcement.published_at.desc(), Announcement.id.desc())
    ).all()
    return [announcement_response(db, row) for row in rows]


def list_managed_announcements(
    db: Session, actor: User, club_id: int
) -> list[dict[str, object]]:
    _club_access(db, actor, club_id)
    rows = db.scalars(
        select(Announcement)
        .where(Announcement.club_id == club_id)
        .order_by(Announcement.created_at.desc(), Announcement.id.desc())
    ).all()
    return [announcement_response(db, row) for row in rows]


def publish_announcement(
    db: Session, actor: User, announcement_id: int
) -> dict[str, object]:
    announcement = db.scalar(
        select(Announcement)
        .where(Announcement.id == announcement_id)
        .with_for_update()
    )
    if announcement is None:
        raise HTTPException(status_code=404, detail="Announcement not found")
    if announcement.club_id is None:
        if actor.role != UserRole.CLUB_ADMIN:
            raise HTTPException(status_code=403, detail="Announcement access denied")
    else:
        _club_access(db, actor, announcement.club_id)
    if announcement.status != AnnouncementStatus.DRAFT:
        raise HTTPException(
            status_code=409, detail="Only draft announcements can be published"
        )
    now = _now()
    if announcement.expires_at is not None and _utc(announcement.expires_at) <= now:
        raise HTTPException(status_code=422, detail="Announcement expiration is in the past")
    announcement.status = AnnouncementStatus.PUBLISHED
    announcement.published_at = now
    _notify_recipients(db, announcement)
    db.add(
        AuditLog(
            actor_id=actor.id,
            action="announcement.published",
            entity_type="announcement",
            entity_id=str(announcement.id),
        )
    )
    db.commit()
    db.refresh(announcement)
    return announcement_response(db, announcement)


def update_announcement(
    db: Session,
    actor: User,
    announcement_id: int,
    data: AnnouncementUpdate,
) -> dict[str, object]:
    announcement = db.scalar(
        select(Announcement)
        .where(Announcement.id == announcement_id)
        .with_for_update()
    )
    if announcement is None:
        raise HTTPException(status_code=404, detail="Announcement not found")
    if announcement.club_id is None:
        if actor.role != UserRole.CLUB_ADMIN:
            raise HTTPException(status_code=403, detail="Announcement access denied")
    else:
        _club_access(db, actor, announcement.club_id)
    if announcement.status != AnnouncementStatus.DRAFT:
        raise HTTPException(status_code=409, detail="Only draft announcements can be edited")
    changes = data.model_dump(exclude_unset=True)
    if "title" in changes and changes["title"] is not None:
        announcement.title = changes["title"].strip()
    if "body" in changes and changes["body"] is not None:
        announcement.body = changes["body"].strip()
    if "expires_at" in changes:
        announcement.expires_at = _utc(changes["expires_at"])
    db.commit()
    db.refresh(announcement)
    return announcement_response(db, announcement)


def cancel_announcement(
    db: Session, actor: User, announcement_id: int
) -> dict[str, object]:
    announcement = db.scalar(
        select(Announcement)
        .where(Announcement.id == announcement_id)
        .with_for_update()
    )
    if announcement is None:
        raise HTTPException(status_code=404, detail="Announcement not found")
    if announcement.club_id is None:
        if actor.role != UserRole.CLUB_ADMIN:
            raise HTTPException(status_code=403, detail="Announcement access denied")
    else:
        _club_access(db, actor, announcement.club_id)
    if announcement.status == AnnouncementStatus.CANCELLED:
        raise HTTPException(status_code=409, detail="Announcement is already cancelled")
    announcement.status = AnnouncementStatus.CANCELLED
    db.add(
        AuditLog(
            actor_id=actor.id,
            action="announcement.cancelled",
            entity_type="announcement",
            entity_id=str(announcement.id),
        )
    )
    db.commit()
    db.refresh(announcement)
    return announcement_response(db, announcement)
