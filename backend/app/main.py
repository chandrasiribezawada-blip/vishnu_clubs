from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.router import api_router
from app.core.config import Settings, get_settings


def create_app(settings: Settings | None = None) -> FastAPI:
    app_settings = settings or get_settings()
    application = FastAPI(
        title="VishnuConnect API",
        version="1.0.0",
        description="API for the VishnuConnect student clubs and events application.",
    )
    if app_settings.cors_origins:
        cors_options = {
            "allow_origins": app_settings.cors_origins,
            "allow_credentials": True,
            "allow_methods": ["GET", "POST", "PATCH", "DELETE"],
            "allow_headers": ["Authorization", "Content-Type"],
        }
        if app_settings.app_env.lower() == "development":
            cors_options["allow_origin_regex"] = (
                r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"
            )
        application.add_middleware(
            CORSMiddleware,
            **cors_options,
        )
    application.include_router(api_router, prefix=app_settings.api_prefix)

    @application.get("/health", tags=["health"])
    def health() -> dict[str, str]:
        return {"status": "ok"}

    return application


app = create_app()
