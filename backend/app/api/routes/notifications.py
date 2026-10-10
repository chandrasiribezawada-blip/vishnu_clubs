from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select

from app.api.dependencies import CurrentUser, DbSession
from app.models.entities import Notification

router = APIRouter(tags=["notifications"])


class NotificationResponse(BaseModel):
    id: int
    title: str
    message: str
    target_path: str | None
    read_at: datetime | None
    created_at: datetime


@router.get("/me/notifications", response_model=list[NotificationResponse])
def list_notifications(db: DbSession, user: CurrentUser) -> list[Notification]:
    return list(
        db.scalars(
            select(Notification)
            .where(Notification.recipient_id == user.id)
            .order_by(Notification.created_at.desc(), Notification.id.desc())
        ).all()
    )


@router.patch(
    "/me/notifications/{notification_id}/read",
    response_model=NotificationResponse,
)
def mark_notification_read(
    notification_id: int, db: DbSession, user: CurrentUser
) -> Notification:
    notification = db.scalar(
        select(Notification)
        .where(
            Notification.id == notification_id,
            Notification.recipient_id == user.id,
        )
        .with_for_update()
    )
    if notification is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Notification not found",
        )
    if notification.read_at is None:
        notification.read_at = datetime.now(UTC)
        db.commit()
        db.refresh(notification)
    return notification
