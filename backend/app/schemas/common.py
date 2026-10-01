from datetime import UTC, datetime


def utc_z(value: datetime) -> str:
    """Serialize a datetime as UTC with a trailing Z, e.g. 2026-10-05T09:00:00Z."""
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")
