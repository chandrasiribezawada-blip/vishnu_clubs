from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

from app.models.entities import UserRole


class RegisterRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    full_name: str = Field(min_length=2, max_length=160)
    email: EmailStr
    registration_number: str = Field(min_length=1, max_length=64)
    department: str = Field(min_length=1, max_length=120)
    year: str = Field(min_length=1, max_length=32)
    section: str | None = Field(default=None, max_length=32)
    phone_number: str = Field(min_length=7, max_length=32)
    password: str = Field(min_length=12, max_length=128)

    @field_validator(
        "full_name",
        "registration_number",
        "department",
        "year",
        "phone_number",
    )
    @classmethod
    def strip_required_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("This field cannot be blank")
        return value


class LoginRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=1)


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    email: EmailStr
    full_name: str
    role: UserRole


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    user: UserResponse


class LogoutResponse(BaseModel):
    detail: str = "Logged out"
