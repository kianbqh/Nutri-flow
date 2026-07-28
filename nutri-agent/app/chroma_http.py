from __future__ import annotations

import hashlib
import math
import re
from typing import Any, Iterable, Sequence

import httpx
from pydantic_settings import BaseSettings, SettingsConfigDict


_TOKEN_RE = re.compile(r"[a-z0-9_]+|[\u4e00-\u9fff]", re.IGNORECASE)


class ChromaHttpSettings(BaseSettings):
    chroma_host: str = "127.0.0.1"
    chroma_port: int = 8100
    chroma_tenant: str = "default_tenant"
    chroma_database: str = "default_database"
    chroma_timeout_seconds: float = 8.0

    model_config = SettingsConfigDict(
        env_prefix="NUTRI_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


_settings = ChromaHttpSettings()


def _base_url() -> str:
    return (
        f"http://{_settings.chroma_host}:{_settings.chroma_port}/api/v2/tenants/"
        f"{_settings.chroma_tenant}/databases/{_settings.chroma_database}"
    )


def _tokenize(text: str) -> list[str]:
    lowered = (text or "").strip().lower()
    if not lowered:
        return ["<empty>"]
    tokens = _TOKEN_RE.findall(lowered)
    return tokens or [lowered]


def embed_text(text: str, dimension: int = 128) -> list[float]:
    vector = [0.0] * dimension
    for token in _tokenize(text):
        digest = hashlib.sha256(token.encode("utf-8")).digest()
        for offset in range(0, min(len(digest), 16), 2):
            bucket = digest[offset] % dimension
            sign = 1.0 if digest[offset + 1] % 2 == 0 else -1.0
            vector[bucket] += sign

    norm = math.sqrt(sum(value * value for value in vector))
    if norm <= 0:
        return vector
    return [value / norm for value in vector]


async def _request(method: str, path: str, json_body: dict[str, Any] | None = None) -> Any:
    async with httpx.AsyncClient(
        timeout=_settings.chroma_timeout_seconds,
        trust_env=False,
    ) as client:
        response = await client.request(method, f"{_base_url()}{path}", json=json_body)
        response.raise_for_status()
        return response.json() if response.content else None


async def get_or_create_collection_id(name: str, metadata: dict[str, Any] | None = None) -> str:
    payload = {
        "name": name,
        "get_or_create": True,
        "metadata": metadata or {},
        "configuration": None,
    }
    collection = await _request("POST", "/collections", payload)
    collection_id = (collection or {}).get("id")
    if not collection_id:
        raise RuntimeError(f"Chroma collection id missing for collection={name}")
    return str(collection_id)


async def upsert_text_records(
    collection_name: str,
    records: Sequence[dict[str, Any]],
    metadata: dict[str, Any] | None = None,
) -> int:
    if not records:
        return 0

    collection_id = await get_or_create_collection_id(collection_name, metadata=metadata)
    ids: list[str] = []
    documents: list[str] = []
    metadatas: list[dict[str, Any]] = []
    embeddings: list[list[float]] = []

    for record in records:
        document = str(record.get("document") or "").strip()
        if not document:
            continue
        ids.append(str(record.get("id") or hashlib.md5(document.encode("utf-8"), usedforsecurity=False).hexdigest()))
        documents.append(document)
        metadatas.append(dict(record.get("metadata") or {}))
        embeddings.append(embed_text(document))

    if not ids:
        return 0

    await _request(
        "POST",
        f"/collections/{collection_id}/upsert",
        {
            "ids": ids,
            "documents": documents,
            "metadatas": metadatas,
            "embeddings": embeddings,
        },
    )
    return len(ids)


async def query_text_records(
    collection_name: str,
    query_text: str,
    n_results: int = 5,
    where: dict[str, Any] | None = None,
    include: Iterable[str] | None = None,
    metadata: dict[str, Any] | None = None,
) -> dict[str, Any]:
    collection_id = await get_or_create_collection_id(collection_name, metadata=metadata)
    payload: dict[str, Any] = {
        "query_embeddings": [embed_text(query_text)],
        "n_results": n_results,
        "include": list(include or ["documents", "metadatas", "distances"]),
    }
    if where:
        payload["where"] = where
    response = await _request("POST", f"/collections/{collection_id}/query", payload)
    return dict(response or {})