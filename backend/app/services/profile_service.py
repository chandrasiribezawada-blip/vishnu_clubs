from sqlalchemy.orm import Session

from app.models.entities import StudentProfile, User


def get_profile(db: Session, user: User) -> dict[str, str | None]:
    profile = db.get(StudentProfile, user.id)
    if profile is None:
        return {}
    return {
        "registration_number": profile.registration_number,
        "department": profile.department,
        "year": profile.year,
        "section": profile.section,
        "phone_number": profile.phone_number,
    }