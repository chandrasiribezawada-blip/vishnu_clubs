from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, model_validator

from app.models.entities import EventRegistrationStatus, EventStatus


class EventCreate(BaseModel):
    title: str = Field(min_length=3, max_length=180)
    description: str | None = Field(default=None, max_length=10000)
    category: str | None = Field(default=None, max_length=80)
    eligibility: str | None = Field(default=None, max_length=500)
    poster_url: HttpUrl | None = None
    start_at: datetime
    end_at: datetime
    registration_opens_at: datetime
    registration_closes_at: datetime
    venue: str = Field(min_length=1, max_length=240)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    capacity: int = Field(gt=0, le=100000)

    @model_validator(mode="after")
    def validate_event_times(self) -> "EventCreate":
        timestamps = (
            self.start_at,
            self.end_at,
            self.registration_opens_at,
            self.registration_closes_at,
        )
        if any(value.tzinfo is None or value.utcoffset() is None for value in timestamps):
            raise ValueError("Event timestamps must include a timezone")
        if self.end_at <= self.start_at:
            raise ValueError("Event end time must be after its start time")
        if self.registration_closes_at < self.registration_opens_at:
            raise ValueError("Registration close time must follow its open time")
        if self.registration_closes_at > self.start_at:
            raise ValueError("Registration must close by the event start time")
        if (self.latitude is None) != (self.longitude is None):
            raise ValueError("Latitude and longitude must be provided together")
        if not self.venue.strip():
            raise ValueError("Venue cannot be blank")
        return self


class EventUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=3, max_length=180)
    description: str | None = Field(default=None, max_length=10000)
    category: str | None = Field(default=None, max_length=80)
    eligibility: str | None = Field(default=None, max_length=500)
    poster_url: HttpUrl | None = None
    start_at: datetime | None = None
    end_at: datetime | None = None
    registration_opens_at: datetime | None = None
    registration_closes_at: datetime | None = None
    venue: str | None = Field(default=None, min_length=1, max_length=240)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    capacity: int | None = Field(default=None, gt=0, le=100000)

    model_config = ConfigDict(extra="forbid")

    @model_validator(mode="after")
    def validate_timezone(self) -> "EventUpdate":
        for name in (
            "start_at",
            "end_at",
            "registration_opens_at",
            "registration_closes_at",
        ):
            value = getattr(self, name)
            if value is not None and (
                value.tzinfo is None or value.utcoffset() is None
            ):
                raise ValueError("Event timestamps must include a timezone")
        if (self.latitude is None) != (self.longitude is None):
            raise ValueError("Latitude and longitude must be provided together")
        return self


class EventResponse(BaseModel):
    id: int
    club_id: int
    club_name: str
    title: str
    description: str | None
    category: str | None
    eligibility: str | None
    poster_url: str | None
    start_at: datetime
    end_at: datetime
    registration_opens_at: datetime
    registration_closes_at: datetime
    venue: str
    latitude: float | None
    longitude: float | None
    capacity: int
    registration_count: int
    status: EventStatus
    created_at: datetime
    updated_at: datetime


class EventRegistrationResponse(BaseModel):
    id: int
    event_id: int
    status: EventRegistrationStatus
    registered_at: datetime
    cancelled_at: datetime | None


class MyEventResponse(EventResponse):
    registration_id: int
    registration_status: EventRegistrationStatus
    registered_at: datetime
    cancelled_at: datetime | None
    attended: bool


class EventTicketResponse(BaseModel):
    ticket_token: str
    expires_at: datetime


class CheckInRequest(BaseModel):
    ticket_token: str = Field(min_length=32, max_length=128)


class CheckInResponse(BaseModel):
    event_id: int
    event_title: str
    checked_in_at: datetime
    result: str


class AttendanceHistoryResponse(BaseModel):
    event_id: int
    event_title: str
    club_name: str
    checked_in_at: datetime
