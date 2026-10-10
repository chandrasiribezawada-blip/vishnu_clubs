from fastapi import APIRouter

from app.api.dependencies import CurrentUser, DbSession
from app.schemas.profile import ProfileResponse
from app.services import profile_service

router = APIRouter(tags=["profile"])


@router.get("/me/profile", response_model=ProfileResponse)
def my_profile(db: DbSession, user: CurrentUser) -> dict[str, str | None]:
    return profile_service.get_profile(db, user)