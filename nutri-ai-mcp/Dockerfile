FROM python:3.11-slim-bookworm

ARG PYTORCH_INDEX_URL=https://download.pytorch.org/whl/cpu

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends libglib2.0-0 libgomp1 \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --system --gid 10001 nutri \
    && useradd --system --uid 10001 --gid nutri --home-dir /app nutri

WORKDIR /app

COPY requirements-runtime.txt .
RUN python -m pip install --upgrade pip \
    && python -m pip install \
        --index-url "${PYTORCH_INDEX_URL}" \
        torch==2.6.0 torchvision==0.21.0 \
    && python -m pip install -r requirements-runtime.txt

COPY app ./app
COPY main.py .

USER nutri
EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
