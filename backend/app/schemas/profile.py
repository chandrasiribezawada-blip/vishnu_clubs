from pydantic import BaseModel


class ProfileResponse(BaseModel):
    registration_number: str | None = None
    department: str | None = None
    year: str | None = None
    section: str | None = None
    phone_number: str | None = None