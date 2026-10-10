from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.models.entities import AnnouncementStatus


class AnnouncementCreate(BaseModel):
    title: str = Field(min_length=3, max_length=180)
    body: str = Field(min_length=1, max_length=10000)
    publish: bool = True
    expires_at: datetime | None = None

    model_config = ConfigDict(extra="forbid")

    @model_validator(mode="after")
    def validate_dates(self) -> "AnnouncementCreate":
        if self.expires_at is not None and (
            self.expires_at.tzinfo is None or self.expires_at.utcoffset() is None
        ):
            raise ValueError("Expiration time must include a timezone")
        if not self.title.strip() or not self.body.strip():
            raise ValueError("Title and body cannot be blank")
        return self


class AnnouncementUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=3, max_length=180)
    body: str | None = Field(default=None, min_length=1, max_length=10000)
    expires_at: datetime | None = None

    model_config = ConfigDict(extra="forbid")

    @model_validator(mode="after")
    def validate_dates(self) -> "AnnouncementUpdate":
        if self.expires_at is not None and (
            self.expires_at.tzinfo is None or self.expires_at.utcoffset() is None
        ):
            raise ValueError("Expiration time must include a timezone")
        return self


class AnnouncementResponse(BaseModel):
    id: int
    club_id: int | None
    club_name: str | None
    title: str
    body: str
    status: AnnouncementStatus
    published_at: datetime | None
    expires_at: datetime | None
    created_at: datetime
    updated_at: datetime
