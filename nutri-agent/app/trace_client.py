from __future__ import annotations

import logging

import httpx
from pydantic_settings import BaseSettings, SettingsConfigDict

logger = logging.getLogger(__name__)


class TraceSettings(BaseSettings):
    business_base_url: str = "http://localhost:8080/api/v1"
    trace_event_key: str = ""

    model_config = SettingsConfigDict(
        env_prefix="NUTRI_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


_settings = TraceSettings()


async def record_trace_event(
    task_id: str,
    stage: str,
    state: str,
    detail: str,
    *,
    service: str = "agent",
    duration_ms: float | None = None,
) -> None:
    """Best-effort structured tracing; failures never block food analysis."""
    if not task_id or not _settings.trace_event_key:
        return

    payload = {
        "taskId": task_id,
        "stage": stage,
        "state": state,
        "service": service,
        "detail": (detail or "")[:512],
        "durationMs": round(duration_ms, 2) if duration_ms is not None else None,
    }
    try:
        async with httpx.AsyncClient(timeout=2.0, trust_env=False) as client:
            response = await client.post(
                f"{_settings.business_base_url.rstrip('/')}/internal/task-traces/events",
                json=payload,
                headers={"X-Nutri-Trace-Key": _settings.trace_event_key},
            )
            response.raise_for_status()
    except Exception as exc:
        logger.warning(
            "Trace event delivery failed task_id=%s stage=%s: %s",
            task_id,
            stage,
            exc,
        )
