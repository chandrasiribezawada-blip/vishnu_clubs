from typing import Annotated

from fastapi import APIRouter, Depends, status

from app.api.dependencies import CurrentUser, DbSession
from app.core.config import Settings, get_settings
from app.models.entities import RefreshSession
from app.schemas.auth import (
    LoginRequest,
    LogoutResponse,
    RefreshRequest,
    RegisterRequest,
    TokenResponse,
    UserResponse,
)
from app.services import auth_service

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def register(
    data: RegisterRequest,
    db: DbSession,
    settings: Annotated[Settings, Depends(get_settings)],
) -> dict[str, object]:
    return auth_service.register_student(db, settings, data)


@router.post("/login", response_model=TokenResponse)
def login(
    data: LoginRequest,
    db: DbSession,
    settings: Annotated[Settings, Depends(get_settings)],
) -> dict[str, object]:
    return auth_service.login(db, settings, data)


@router.post("/refresh", response_model=TokenResponse)
def refresh(
    data: RefreshRequest,
    db: DbSession,
    settings: Annotated[Settings, Depends(get_settings)],
) -> dict[str, object]:
    return auth_service.refresh(db, settings, data.refresh_token)


@router.post("/logout", response_model=LogoutResponse)
def logout(
    data: RefreshRequest,
    db: DbSession,
    settings: Annotated[Settings, Depends(get_settings)],
    _user: CurrentUser,
) -> LogoutResponse:
    auth_service.revoke_session(db, settings, data.refresh_token, _user.id)
    return LogoutResponse()


@router.get("/me", response_model=UserResponse)
def me(user: CurrentUser) -> UserResponse:
    return UserResponse.model_validate(user)
