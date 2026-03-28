#!/usr/bin/env bash
# .devcontainer/postCreate.sh
# ---------------------------------------------------------------------------
# Runs once after the devcontainer is created.
# 1. Create .env from .env.example, rewriting service host references from
#    "localhost" to the Docker Compose service names so the applications
#    running inside the devcontainer can reach the infra containers.
# 2. Install Node.js dependencies for nutri-web.
# 3. Install Python dependencies for nutri-agent and nutri-ai-mcp.
#    Note: nutri-ai-mcp includes large ML wheels (PyTorch, torchvision);
#    the first install will take several minutes.
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ── 1. Configure .env for Docker Compose networking ────────────────────────
if [ ! -f .env ]; then
  echo "→ Creating .env from .env.example ..."
  cp .env.example .env

  # Replace localhost references with Docker Compose service names
  sed -i 's|localhost:3306|mysql:3306|g'                                              .env
  sed -i 's|SPRING_RABBITMQ_HOST=localhost|SPRING_RABBITMQ_HOST=rabbitmq|g'           .env
  sed -i 's|SPRING_DATA_REDIS_HOST=localhost|SPRING_DATA_REDIS_HOST=redis|g'          .env
  sed -i 's|OSS_ENDPOINT=http://localhost:9000|OSS_ENDPOINT=http://minio:9000|g'      .env
  sed -i 's|NUTRI_RABBITMQ_URL=amqp://nutri_mq:nutri_mq_pass@localhost:5672/|NUTRI_RABBITMQ_URL=amqp://nutri_mq:nutri_mq_pass@rabbitmq:5672/|g' .env
  sed -i 's|NUTRI_MCP_SERVER_URL=http://localhost:8000/mcp|NUTRI_MCP_SERVER_URL=http://nutri-ai-mcp:8000/mcp|g' .env
  sed -i 's|NUTRI_CHROMA_HOST=localhost|NUTRI_CHROMA_HOST=chroma|g'                   .env
  sed -i 's|NUTRI_CHROMA_PORT=8100|NUTRI_CHROMA_PORT=8000|g'                          .env

  echo "  .env created.  Remember to fill in NUTRI_MOONSHOT_API_KEY."
else
  echo "→ .env already exists, skipping creation."
fi

# ── 2. Node.js dependencies (nutri-web) ────────────────────────────────────
echo "→ Installing Node.js dependencies for nutri-web ..."
cd "$REPO_ROOT/nutri-web" && npm install

# ── 3. Python dependencies ─────────────────────────────────────────────────
echo "→ Installing Python dependencies for nutri-agent ..."
cd "$REPO_ROOT/nutri-agent" && pip install -r requirements.txt

echo "→ Installing Python dependencies for nutri-ai-mcp (may take a few minutes) ..."
cd "$REPO_ROOT/nutri-ai-mcp" && pip install -r requirements.txt

echo ""
echo "✅  Devcontainer setup complete."
echo "    Next steps:"
echo "    • Set NUTRI_MOONSHOT_API_KEY in .env"
echo "    • nutri-web:      cd nutri-web && npm run dev"
echo "    • nutri-business: cd nutri-business && mvn spring-boot:run"
echo "    • nutri-ai-mcp:   cd nutri-ai-mcp && python main.py"
echo "    • nutri-agent:    cd nutri-agent && python main.py"
