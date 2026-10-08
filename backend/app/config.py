from functools import lru_cache
from typing import Annotated, Literal

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


class Settings(BaseSettings):
    """Application configuration, read only from environment variables."""

    model_config = SettingsConfigDict(extra="ignore")

    app_name: str = "Spry API"
    app_env: Literal["development", "test", "production"] = "development"
    log_level: str = "info"

    database_url: str = "postgresql+asyncpg://spry:spry@db:5432/spry"
    # False on Lambda: an idle execution environment must not hold connections
    # open, or Aurora Serverless never pauses.
    db_pooling: bool = True

    # NoDecode: accept the comma-separated string Compose passes, not JSON.
    cors_origins: Annotated[list[str], NoDecode] = Field(
        default_factory=lambda: ["http://localhost:5173"]
    )

    # Cognito. Configured: every /api route needs a valid access token.
    # Not configured: development and tests run as one local user; production
    # answers 503 - a missing setting must never leave the API open.
    cognito_region: str = "us-east-1"
    cognito_user_pool_id: str = ""
    cognito_client_id: str = ""
    # The pool's public keys as JSON. Set on Lambda, which has no route to the
    # internet to download them; empty elsewhere, and they are fetched.
    cognito_jwks: str = ""

    @property
    def cognito_issuer(self) -> str:
        host = f"https://cognito-idp.{self.cognito_region}.amazonaws.com"
        return f"{host}/{self.cognito_user_pool_id}"

    @property
    def auth_configured(self) -> bool:
        return bool(self.cognito_user_pool_id and self.cognito_client_id)

    @field_validator("cors_origins", mode="before")
    @classmethod
    def _split_origins(cls, value: object) -> object:
        if isinstance(value, str):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        return value


@lru_cache
def get_settings() -> Settings:
    return Settings()
