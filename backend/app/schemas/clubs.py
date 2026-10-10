from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.models.entities import JoinRequestStatus


class ClubResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    category: str | None
    description: str | None
    objectives: str | None
    contact_email: str | None
    member_count: int = 0
    follower_count: int = 0


class JoinRequestCreate(BaseModel):
    reason: str = Field(min_length=20, max_length=400)
    skills: str = Field(min_length=1, max_length=200)
    experience: str | None = Field(default=None, max_length=300)

    @field_validator("reason")
    @classmethod
    def normalize_reason(cls, value: str) -> str:
        value = value.strip()
        if len(value) < 20:
            raise ValueError("Reason must contain at least 20 non-whitespace characters")
        return value

    @field_validator("skills")
    @classmethod
    def normalize_skills(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Skills cannot be blank")
        return value


class JoinRequestResponse(BaseModel):
    id: int
    club_id: int
    club_name: str
    student_id: str
    student_name: str
    student_email: str
    reason: str
    skills: str
    experience: str | None
    status: JoinRequestStatus
    created_at: datetime
    decided_at: datetime | None


class DecisionRequest(BaseModel):
    note: str | None = Field(default=None, max_length=500)


class MembershipResponse(BaseModel):
    id: int
    club_id: int
    club_name: str
    created_at: datetime
