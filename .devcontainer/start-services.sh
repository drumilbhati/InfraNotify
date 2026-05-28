#!/usr/bin/env bash

ROOT="/workspaces/InfraNotify"
LOG_DIR="$ROOT/.devcontainer/logs"

mkdir -p "$LOG_DIR"

start_java_service() {
  local dir="$1"
  local name

  if [ ! -f "$dir/pom.xml" ]; then
    return
  fi

  name="$(basename "$dir")"
  echo "Starting $name..."
  nohup "$dir/mvnw" -q -DskipTests spring-boot:run > "$LOG_DIR/${name}.log" 2>&1 &
}

start_java_service "$ROOT/services/api-gateway"
start_java_service "$ROOT/services/auth-service"
start_java_service "$ROOT/services/metrics-ingestion-service"
start_java_service "$ROOT/services/alert-engine-service"
start_java_service "$ROOT/services/notification-service"
start_java_service "$ROOT/services/health-poller-service"
start_java_service "$ROOT/services/analytics-service"

if [ -s "$ROOT/services/notification-service/main.js" ]; then
  echo "Starting notification-service (node)..."
  nohup node "$ROOT/services/notification-service/main.js" > "$LOG_DIR/notification-service.log" 2>&1 &
fi

if [ -f "$ROOT/client/dashboard/package.json" ]; then
  echo "Starting dashboard..."
  (cd "$ROOT/client/dashboard" && nohup npm run dev > "$LOG_DIR/dashboard.log" 2>&1 &)
fi
