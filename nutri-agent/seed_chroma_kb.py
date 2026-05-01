from __future__ import annotations

import asyncio
import hashlib
import json
import os
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

from app.chroma_http import upsert_text_records


class SeedSettings(BaseSettings):
    chroma_host: str = "127.0.0.1"
    chroma_port: int = 8100
    chroma_nutrition_collection: str = "nutrition_knowledge"
    local_kb_path: str = "app/nodes/nutrition_kb.json"

    model_config = SettingsConfigDict(
        env_prefix="NUTRI_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


def _load_kb(path: Path) -> dict[str, str]:
    with path.open("r", encoding="utf-8") as handle:
        raw = json.load(handle)
    return {str(key).strip().lower(): str(value).strip() for key, value in raw.items()}


async def main() -> None:
    settings = SeedSettings()
    kb_path = Path(settings.local_kb_path)
    if not kb_path.is_absolute():
        kb_path = Path(__file__).resolve().parent / kb_path

    if not kb_path.exists():
        raise FileNotFoundError(f"Nutrition KB file not found: {kb_path}")

    kb = _load_kb(kb_path)
    records: list[dict[str, object]] = []

    for label, text in kb.items():
        stable_id = hashlib.md5(label.encode("utf-8"), usedforsecurity=False).hexdigest()
        records.append(
            {
                "id": f"nutrition-{stable_id}",
                "document": f"{label}: {text}",
                "metadata": {"label": label, "source": "nutrition_kb.json"},
            }
        )

    upserted = await upsert_text_records(
        settings.chroma_nutrition_collection,
        records,
        metadata={"domain": "nutrition"},
    )
    print(
        json.dumps(
            {
                "collection": settings.chroma_nutrition_collection,
                "count": upserted,
                "kbPath": os.fspath(kb_path),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    asyncio.run(main())