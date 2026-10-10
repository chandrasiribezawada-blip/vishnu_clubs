import argparse
from getpass import getpass

from sqlalchemy import select

from app.core.security import hash_password
from app.database.session import get_session_factory
from app.models.entities import User, UserRole


def main() -> None:
    parser = argparse.ArgumentParser(description="Create the first VishnuConnect admin.")
    parser.add_argument("--email", required=True)
    parser.add_argument("--name", required=True)
    args = parser.parse_args()

    password = getpass("Admin password (minimum 12 characters): ")
    if len(password) < 12:
        parser.error("Password must contain at least 12 characters")

    with get_session_factory()() as db:
        existing_admin = db.scalar(
            select(User.id).where(User.role == UserRole.CLUB_ADMIN)
        )
        if existing_admin is not None:
            parser.error("An admin already exists; refusing to create another bootstrap admin")
        email = args.email.strip().lower()
        if db.scalar(select(User.id).where(User.email == email)) is not None:
            parser.error("That email is already registered")
        db.add(
            User(
                email=email,
                full_name=args.name.strip(),
                password_hash=hash_password(password),
                role=UserRole.CLUB_ADMIN,
            )
        )
        db.commit()
    print("Initial admin created.")


if __name__ == "__main__":
    main()
