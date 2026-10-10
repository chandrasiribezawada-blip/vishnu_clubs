from functools import lru_cache

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_env: str = "development"
    database_url: str = (
        "postgresql+psycopg://vishnuconnect:vishnuconnect"
        "@localhost:5432/vishnuconnect"
    )
    jwt_secret_key: str = Field(
        default="development-only-replace-with-a-random-64-character-secret-key",
        min_length=32,
    )
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = Field(default=15, ge=1, le=1440)
    refresh_token_days: int = Field(default=30, ge=1, le=365)
    api_prefix: str = "/api/v1"
    cors_origins: list[str] = Field(default_factory=list)

    @model_validator(mode="after")
    def require_production_secret(self) -> "Settings":
        if self.app_env.lower() == "production" and self.jwt_secret_key.startswith(
            "development-only-"
        ):
            raise ValueError("JWT_SECRET_KEY must be set to a production secret")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
