from fastapi.testclient import TestClient

from app.core.config import Settings
from app.main import create_app


def test_development_cors_allows_flutter_localhost_dev_ports():
    settings = Settings(
        app_env="development",
        database_url="sqlite+pysqlite:///:memory:",
        jwt_secret_key="test-secret-key-with-at-least-thirty-two-characters",
        cors_origins=["http://localhost:3000"],
    )
    client = TestClient(create_app(settings))

    response = client.options(
        "/api/v1/auth/me",
        headers={
            "Origin": "http://localhost:54765",
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "authorization",
        },
    )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == (
        "http://localhost:54765"
    )


def test_production_cors_rejects_unconfigured_localhost_ports():
    settings = Settings(
        app_env="production",
        database_url="sqlite+pysqlite:///:memory:",
        jwt_secret_key="test-secret-key-with-at-least-thirty-two-characters",
        cors_origins=["http://localhost:3000"],
    )
    client = TestClient(create_app(settings))

    response = client.options(
        "/api/v1/auth/me",
        headers={
            "Origin": "http://localhost:54765",
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "authorization",
        },
    )

    assert response.status_code == 400
    assert "access-control-allow-origin" not in response.headers
