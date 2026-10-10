import os
import sys

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.security import hash_password, verify_password
from app.database.session import get_session_factory
from app.models.entities import Club, ClubCoordinator, User, UserRole


def _required(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise ValueError(f"{name} must be set")
    return value


def _seed_user(
    db: Session,
    *,
    email: str,
    password: str,
    role: UserRole,
) -> User:
    normalized_email = email.lower()
    user = db.scalar(select(User).where(User.email == normalized_email))
    if user is None:
        user = User(
            email=normalized_email,
            full_name=normalized_email.split("@", 1)[0].replace(".", " ").title(),
            password_hash=hash_password(password),
            role=role,
        )
        db.add(user)
        db.flush()
    else:
        if not verify_password(password, user.password_hash):
            raise ValueError(f"Existing account {email} has a different password")
        if user.role not in {
            role,
            UserRole.STUDENT,
            UserRole.CLUB_MEMBER_COORDINATOR,
        }:
            raise ValueError(f"Existing account {email} has an incompatible role")
        user.role = role
    return user


def main() -> int:
    try:
        admin_email = _required("SEED_ADMIN_EMAIL")
        admin_password = _required("SEED_ADMIN_PASSWORD")
        coordinator_email = _required("SEED_COORD_EMAIL")
        coordinator_password = _required("SEED_COORD_PASSWORD")
        club_name = _required("SEED_COORD_CLUB_NAME")
        if admin_email.lower() == coordinator_email.lower():
            raise ValueError("Admin and coordinator emails must be different")
        if len(admin_password) < 12 or len(coordinator_password) < 12:
            raise ValueError("Seed passwords must be at least 12 characters")

        with get_session_factory()() as db:
            club = db.scalar(
                select(Club).where(func.lower(Club.name) == club_name.lower())
            )
            if club is None:
                raise ValueError(f"Club {club_name!r} does not exist")
            _seed_user(
                db,
                email=admin_email,
                password=admin_password,
                role=UserRole.CLUB_ADMIN,
            )
            coordinator = _seed_user(
                db,
                email=coordinator_email,
                password=coordinator_password,
                role=UserRole.CLUB_MEMBER_COORDINATOR,
            )
            assignment = db.scalar(
                select(ClubCoordinator).where(
                    ClubCoordinator.user_id == coordinator.id,
                    ClubCoordinator.club_id == club.id,
                    ClubCoordinator.revoked_at.is_(None),
                )
            )
            if assignment is None:
                db.add(ClubCoordinator(user_id=coordinator.id, club_id=club.id))
            db.commit()
        print("Seeded admin and assigned coordinator accounts.")
        return 0
    except (ValueError, RuntimeError) as error:
        print(f"Role seeding failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())