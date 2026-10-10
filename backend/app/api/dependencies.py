from typing import Annotated
from datetime import UTC, datetime
from uuid import UUID

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.security import decode_token
from app.database.session import get_db
from app.models.entities import RefreshSession, User, UserRole

bearer_scheme = HTTPBearer(auto_error=False)
DbSession = Annotated[Session, Depends(get_db)]


def get_current_user(
    credentials: Annotated[
        HTTPAuthorizationCredentials | None, Depends(bearer_scheme)
    ],
    db: DbSession,
    settings: Annotated[Settings, Depends(get_settings)],
) -> User:
    unauthorized = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Authentication required",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if credentials is None:
        raise unauthorized
    try:
        claims = decode_token(settings, credentials.credentials, "access")
        user_id = UUID(str(claims["sub"]))
        session_id = UUID(str(claims["sid"]))
    except (jwt.InvalidTokenError, KeyError, ValueError, TypeError):
        raise unauthorized from None

    session = db.get(RefreshSession, session_id)
    user = db.get(User, user_id)
    if (
        session is None
        or session.user_id != user_id
        or session.revoked_at is not None
        or _as_utc(session.expires_at) <= datetime.now(UTC)
        or user is None
        or not user.is_active
    ):
        raise unauthorized
    return user


def _as_utc(value: datetime) -> datetime:
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value


def require_roles(*roles: UserRole):
    allowed = set(roles)

    def dependency(user: Annotated[User, Depends(get_current_user)]) -> User:
        if user.role not in allowed:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You do not have permission to perform this action",
            )
        return user

    return dependency


CurrentUser = Annotated[User, Depends(get_current_user)]
StudentUser = Annotated[User, Depends(require_roles(UserRole.STUDENT))]
CoordinatorUser = Annotated[
    User, Depends(require_roles(UserRole.CLUB_MEMBER_COORDINATOR))
]
AdminUser = Annotated[User, Depends(require_roles(UserRole.CLUB_ADMIN))]
CoordinatorOrAdmin = Annotated[
    User,
    Depends(
        require_roles(UserRole.CLUB_MEMBER_COORDINATOR, UserRole.CLUB_ADMIN)
    ),
]
