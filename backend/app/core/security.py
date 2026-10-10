import hashlib
import secrets
from datetime import UTC, datetime, timedelta
from uuid import UUID

import jwt
from pwdlib import PasswordHash

from app.core.config import Settings

password_hash = PasswordHash.recommended()


def hash_password(password: str) -> str:
    return password_hash.hash(password)


def verify_password(password: str, hashed: str) -> bool:
    return password_hash.verify(password, hashed)


def digest_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def create_access_token(
    settings: Settings,
    user_id: UUID,
    role: str,
    session_id: UUID,
) -> tuple[str, datetime]:
    expires_at = datetime.now(UTC) + timedelta(minutes=settings.access_token_minutes)
    claims = {
        "sub": str(user_id),
        "role": role,
        "sid": str(session_id),
        "typ": "access",
        "iat": datetime.now(UTC),
        "exp": expires_at,
    }
    return jwt.encode(claims, settings.jwt_secret_key, algorithm=settings.jwt_algorithm), expires_at


def create_refresh_token(
    settings: Settings,
    user_id: UUID,
    session_id: UUID,
) -> tuple[str, datetime]:
    expires_at = datetime.now(UTC) + timedelta(days=settings.refresh_token_days)
    claims = {
        "sub": str(user_id),
        "sid": str(session_id),
        "jti": secrets.token_urlsafe(24),
        "typ": "refresh",
        "iat": datetime.now(UTC),
        "exp": expires_at,
    }
    return jwt.encode(claims, settings.jwt_secret_key, algorithm=settings.jwt_algorithm), expires_at


def decode_token(settings: Settings, token: str, expected_type: str) -> dict[str, object]:
    claims = jwt.decode(
        token,
        settings.jwt_secret_key,
        algorithms=[settings.jwt_algorithm],
        options={"require": ["sub", "sid", "exp", "iat", "typ"]},
    )
    if claims.get("typ") != expected_type:
        raise jwt.InvalidTokenError("Unexpected token type")
    return claims
