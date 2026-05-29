#!/usr/bin/env bash

ROOT="/workspaces/InfraNotify"
LOG_DIR="$ROOT/.devcontainer/logs"

mkdir -p "$LOG_DIR"

kill_port_listeners() {
  local port="$1"
  local pids

  pids=$(ss -ltnp "sport = :$port" 2>/dev/null | awk -F'pid=' '{for (i=2; i<=NF; i++) {split($i,a,","); print a[1]}}' | sort -u)

  if [ -n "$pids" ]; then
    echo "Stopping processes on port $port: $pids"
    kill -TERM $pids 2>/dev/null || true

    pids=$(ss -ltnp "sport = :$port" 2>/dev/null | awk -F'pid=' '{for (i=2; i<=NF; i++) {split($i,a,","); print a[1]}}' | sort -u)
    if [ -n "$pids" ]; then
      echo "Force stopping processes on port $port: $pids"
      kill -KILL $pids 2>/dev/null || true
    fi
  fi
}

bootstrap_maven_wrapper() {
  local dir="$1"

  if [ -x "$dir/mvnw" ]; then
    echo "Bootstrapping Maven wrapper..."
    (cd "$dir" && ./mvnw -q -DskipTests -version) > "$LOG_DIR/maven-wrapper.log" 2>&1
  fi
}

start_java_service() {
  local dir="$1"
  local name

  if [ ! -f "$dir/pom.xml" ]; then
    return
  fi

  name="$(basename "$dir")"
  echo "Starting $name..."
  (
    cd "$dir" || exit 1
    nohup ./mvnw -q -DskipTests spring-boot:run > "$LOG_DIR/${name}.log" 2>&1 &
  )
}

bootstrap_maven_wrapper "$ROOT/services/api-gateway"

# Free common dev ports before starting services.
for port in 3000 8080 8081 8082 8083 8084 8085 8086; do
  kill_port_listeners "$port"
done

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

# start ssh, so that the external agents can connect to the workspace
sudo apt update
sudo apt install -y openssh-server
# always reset password on container start
echo 'node:infranotify' | sudo chpasswd
# start ssh daemon
sudo service ssh start