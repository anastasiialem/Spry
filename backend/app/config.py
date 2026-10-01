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

    @field_validator("cors_origins", mode="before")
    @classmethod
    def _split_origins(cls, value: object) -> object:
        if isinstance(value, str):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        return value


@lru_cache
def get_settings() -> Settings:
    return Settings()
