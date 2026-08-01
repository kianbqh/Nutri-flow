#!/usr/bin/env bash
set -euo pipefail

TASK_ID="${1:-}"
SINCE="${2:-2h}"

if [[ ! "$TASK_ID" =~ ^[0-9a-fA-F-]{36}$ ]]; then
  echo "Usage: $0 <task-uuid> [since, default: 2h]" >&2
  exit 2
fi

cd "$(dirname "$0")/.."

echo "== task logs: $TASK_ID (since $SINCE) =="
docker compose --env-file .env.prod -f compose.prod.yml logs \
  --since "$SINCE" gateway business agent inference 2>&1 \
  | grep -F "$TASK_ID" || true

echo
echo "== queue health =="
docker compose --env-file .env.prod -f compose.prod.yml exec -T rabbitmq \
  rabbitmqctl list_queues name messages_ready messages_unacknowledged consumers

echo
echo "== current task row =="
docker compose --env-file .env.prod -f compose.prod.yml exec -T mysql sh -lc \
  "MYSQL_PWD=\"\$MYSQL_PASSWORD\" mysql -N -u\"\$MYSQL_USER\" \"\$MYSQL_DATABASE\" -e \"SELECT task_id,meal_type,logged_at,IF(analysis_result IS NULL,'PENDING','COMPLETED') AS status FROM diet_logs WHERE task_id='$TASK_ID' LIMIT 1;\""
