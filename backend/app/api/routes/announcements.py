from fastapi import APIRouter

from app.api.dependencies import CoordinatorOrAdmin, CurrentUser, DbSession
from app.schemas.announcements import (
    AnnouncementCreate,
    AnnouncementResponse,
    AnnouncementUpdate,
)
from app.services import announcement_service

router = APIRouter(tags=["announcements"])


@router.get("/announcements", response_model=list[AnnouncementResponse])
def list_announcements(db: DbSession, user: CurrentUser) -> list[dict[str, object]]:
    return announcement_service.list_student_announcements(db, user)


@router.get(
    "/clubs/{club_id}/announcements",
    response_model=list[AnnouncementResponse],
)
def list_club_announcements(
    club_id: int, db: DbSession
) -> list[dict[str, object]]:
    return announcement_service.list_club_announcements(db, club_id)


@router.get(
    "/clubs/{club_id}/announcements/manage",
    response_model=list[AnnouncementResponse],
)
def list_managed_announcements(
    club_id: int, db: DbSession, actor: CoordinatorOrAdmin
) -> list[dict[str, object]]:
    return announcement_service.list_managed_announcements(db, actor, club_id)


@router.post(
    "/clubs/{club_id}/announcements",
    response_model=AnnouncementResponse,
    status_code=201,
)
def create_club_announcement(
    club_id: int,
    data: AnnouncementCreate,
    db: DbSession,
    actor: CoordinatorOrAdmin,
) -> dict[str, object]:
    return announcement_service.create_announcement(
        db, actor, data, club_id=club_id
    )


@router.patch(
    "/announcements/{announcement_id}",
    response_model=AnnouncementResponse,
)
def update_announcement(
    announcement_id: int,
    data: AnnouncementUpdate,
    db: DbSession,
    actor: CoordinatorOrAdmin,
) -> dict[str, object]:
    return announcement_service.update_announcement(
        db, actor, announcement_id, data
    )


@router.post(
    "/announcements/{announcement_id}/publish",
    response_model=AnnouncementResponse,
)
def publish_announcement(
    announcement_id: int, db: DbSession, actor: CoordinatorOrAdmin
) -> dict[str, object]:
    return announcement_service.publish_announcement(
        db, actor, announcement_id
    )


@router.post(
    "/announcements/{announcement_id}/cancel",
    response_model=AnnouncementResponse,
)
def cancel_announcement(
    announcement_id: int, db: DbSession, actor: CoordinatorOrAdmin
) -> dict[str, object]:
    return announcement_service.cancel_announcement(
        db, actor, announcement_id
    )
