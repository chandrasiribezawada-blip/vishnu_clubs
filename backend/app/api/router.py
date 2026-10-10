from fastapi import APIRouter

from app.api.routes import (
    admin,
    announcements,
    auth,
    clubs,
    coordinator,
    events,
    notifications,
    profile,
)

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(clubs.router)
api_router.include_router(coordinator.router)
api_router.include_router(admin.router)
api_router.include_router(events.router)
api_router.include_router(notifications.router)
api_router.include_router(announcements.router)
api_router.include_router(profile.router)