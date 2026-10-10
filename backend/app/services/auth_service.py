from datetime import UTC, datetime
from uuid import UUID, uuid4

import jwt
from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    digest_token,
    hash_password,
    verify_password,
)
from app.models.entities import (
    RefreshSession,
    StudentProfile,
    User,
    UserRole,
)
from app.schemas.auth import LoginRequest, RegisterRequest


def _issue_tokens(db: Session, settings: Settings, user: User) -> dict[str, object]:
    session_id = uuid4()
    access_token, access_expiry = create_access_token(
        settings, user.id, user.role.value, session_id
    )
    refresh_token, refresh_expiry = create_refresh_token(
        settings, user.id, session_id
    )
    db.add(
        RefreshSession(
            id=session_id,
            user_id=user.id,
            refresh_token_digest=digest_token(refresh_token),
            expires_at=refresh_expiry,
        )
    )
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "expires_in": int((access_expiry - datetime.now(UTC)).total_seconds()),
        "user": user,
    }


def register_student(db: Session, settings: Settings, data: RegisterRequest) -> dict[str, object]:
    user = User(
        email=str(data.email).lower(),
        full_name=data.full_name,
        password_hash=hash_password(data.password),
        role=UserRole.STUDENT,
    )
    db.add(user)
    try:
        db.flush()
        db.add(
            StudentProfile(
                user_id=user.id,
                registration_number=data.registration_number,
                department=data.department,
                year=data.year,
                section=data.section,
                phone_number=data.phone_number,
            )
        )
        tokens = _issue_tokens(db, settings, user)
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email or registration number is already registered",
        ) from exc
    db.refresh(user)
    tokens["user"] = user
    return tokens


def login(db: Session, settings: Settings, data: LoginRequest) -> dict[str, object]:
    user = db.scalar(select(User).where(User.email == str(data.email).lower()))
    if (
        user is None
        or not user.is_active
        or not verify_password(data.password, user.password_hash)
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    tokens = _issue_tokens(db, settings, user)
    db.commit()
    return tokens


def refresh(db: Session, settings: Settings, token: str) -> dict[str, object]:
    try:
        claims = decode_token(settings, token, "refresh")
        user_id = UUID(str(claims["sub"]))
        session_id = UUID(str(claims["sid"]))
    except (jwt.InvalidTokenError, KeyError, ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token"
        ) from None

    session = db.scalar(
        select(RefreshSession)
        .where(RefreshSession.id == session_id)
        .with_for_update()
    )
    user = db.get(User, user_id)
    now = datetime.now(UTC)
    if (
        session is None
        or user is None
        or not user.is_active
        or session.user_id != user_id
        or session.revoked_at is not None
        or _as_utc(session.expires_at) <= now
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh session expired"
        )
    if session.refresh_token_digest != digest_token(token):
        session.revoked_at = now
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token reuse detected; session revoked",
        )

    access_token, access_expiry = create_access_token(
        settings, user.id, user.role.value, session.id
    )
    new_refresh_token, refresh_expiry = create_refresh_token(
        settings, user.id, session.id
    )
    session.refresh_token_digest = digest_token(new_refresh_token)
    session.expires_at = refresh_expiry
    db.commit()
    return {
        "access_token": access_token,
        "refresh_token": new_refresh_token,
        "expires_in": int((access_expiry - now).total_seconds()),
        "user": user,
    }


def revoke_session(
    db: Session, settings: Settings, token: str | None, user_id: UUID
) -> None:
    if token is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token required"
        )
    try:
        claims = decode_token(settings, token, "refresh")
        session_id = UUID(str(claims["sid"]))
    except (jwt.InvalidTokenError, KeyError, ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token"
        ) from None
    session = db.get(RefreshSession, session_id)
    if (
        session is None
        or session.user_id != user_id
        or session.revoked_at is not None
        or _as_utc(session.expires_at) <= datetime.now(UTC)
        or session.refresh_token_digest != digest_token(token)
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token is invalid or no longer active",
        )
    session.revoked_at = datetime.now(UTC)
    db.commit()


def _as_utc(value: datetime) -> datetime:
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value
