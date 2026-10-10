from sqlalchemy import select

from app.database.session import get_session_factory
from app.models.entities import Club

CLUB_NAMES = (
    "EAGLE Club – Elite Anti-Narcotics Group for Law Enforcement",
    "TechPost ClubCode",
    "Energy Swaraj Club",
    "CodeChef SVECW Chapter",
    "A A A Club",
    "Eco Club",
    "Idea Club",
    "Painting Club",
    "Music Club",
    "ToastMasters Club",
    "Sahaya Club",
    "Vishnu Cultural Club",
    "Flash It Out Club",
    "Page Turners",
    "Hobby Horses – Techni Safoos",
    "Rock Me Fab",
    "THE HINDU – Future INDIA Club",
    "MECOW Club",
    "ECHARTS",
    "TECHXTREME Coding Club",
    "Dance Club",
    "Empathy Club",
    "Mathletes Club",
)

CLUB_CATEGORIES = {
    CLUB_NAMES[0]: "Social Impact",
    CLUB_NAMES[1]: "Technical",
    CLUB_NAMES[2]: "Environment",
    CLUB_NAMES[3]: "Technical",
    CLUB_NAMES[4]: "General",
    CLUB_NAMES[5]: "Environment",
    CLUB_NAMES[6]: "General",
    CLUB_NAMES[7]: "Arts & Culture",
    CLUB_NAMES[8]: "Arts & Culture",
    CLUB_NAMES[9]: "Literary",
    CLUB_NAMES[10]: "Social Impact",
    CLUB_NAMES[11]: "Arts & Culture",
    CLUB_NAMES[12]: "General",
    CLUB_NAMES[13]: "Literary",
    CLUB_NAMES[14]: "General",
    CLUB_NAMES[15]: "General",
    CLUB_NAMES[16]: "Literary",
    CLUB_NAMES[17]: "General",
    CLUB_NAMES[18]: "General",
    CLUB_NAMES[19]: "Technical",
    CLUB_NAMES[20]: "Arts & Culture",
    CLUB_NAMES[21]: "Social Impact",
    CLUB_NAMES[22]: "Technical",
}

LEGACY_CLUB_NAMES = {
    "EAGLE Club - Elite Anti-Narcotics Group for Law Enforcement":
        "EAGLE Club – Elite Anti-Narcotics Group for Law Enforcement",
    "Hobby Horses-Techni Safoos": "Hobby Horses – Techni Safoos",
    "THE HINDU- Future INDIA Club": "THE HINDU – Future INDIA Club",
}


def seed() -> None:
    with get_session_factory()() as db:
        existing = set(db.scalars(select(Club.name)).all())
        for legacy_name, official_name in LEGACY_CLUB_NAMES.items():
            if legacy_name not in existing:
                continue
            if official_name in existing:
                raise RuntimeError(
                    f"Both legacy and canonical club records exist: {official_name}"
                )
            club = db.scalar(select(Club).where(Club.name == legacy_name))
            if club is not None:
                club.name = official_name
                existing.remove(legacy_name)
                existing.add(official_name)
        for name in CLUB_NAMES:
            if name not in existing:
                db.add(Club(name=name, category=CLUB_CATEGORIES[name]))
                continue
            club = db.scalar(select(Club).where(Club.name == name))
            if club is not None and club.category is None:
                club.category = CLUB_CATEGORIES[name]
        db.commit()


if __name__ == "__main__":
    seed()
