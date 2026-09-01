#!/usr/bin/env bash
# ==============================================================================
# SonarQube on Podman for record-app
# ==============================================================================
#   ./scripts/sonarqube.sh start   - create or resume SonarQube + Postgres
#   ./scripts/sonarqube.sh stop    - stop both containers
#   ./scripts/sonarqube.sh status  - container state and server health
#   ./scripts/sonarqube.sh logs    - stream SonarQube logs
#   ./scripts/sonarqube.sh clean   - remove containers and volumes
# ==============================================================================

set -euo pipefail

SONAR_CONTAINER="sonarqube"
SONAR_IMAGE="docker.io/library/sonarqube:26.8.0.126808-community"
SONAR_PORT="9000"
SONAR_MEMORY="4g"

DB_CONTAINER="sonarqube-db"
DB_IMAGE="docker.io/library/postgres:17"
DB_NAME="sonar"
DB_USER="sonar"
DB_PASSWORD="sonar"

DATA_VOLUME="sonarqube_data"
EXT_VOLUME="sonarqube_extensions"
LOGS_VOLUME="sonarqube_logs"
DB_VOLUME="sonarqube_db_data"

NETWORK="sonarqube-net"

HEALTH_TIMEOUT_SECONDS=300

ensure_podman() {
  if ! command -v podman >/dev/null 2>&1; then
    echo "Error: podman is not installed or not in PATH." >&2
    exit 1
  fi
  if ! podman info >/dev/null 2>&1; then
    echo "Podman machine is not running. Starting it..."
    podman machine start
  fi
}

ensure_network() {
  if ! podman network exists "$NETWORK"; then
    podman network create "$NETWORK" >/dev/null
  fi
}

container_exists() {
  podman container exists "$1"
}

container_running() {
  [[ "$(podman inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" == "true" ]]
}

start_db() {
  if container_running "$DB_CONTAINER"; then
    echo "Postgres already running."
    return
  fi
  if container_exists "$DB_CONTAINER"; then
    echo "Resuming Postgres..."
    podman start "$DB_CONTAINER" >/dev/null
    return
  fi
  echo "Creating Postgres..."
  podman run -d \
    --name "$DB_CONTAINER" \
    --network "$NETWORK" \
    -e POSTGRES_DB="$DB_NAME" \
    -e POSTGRES_USER="$DB_USER" \
    -e POSTGRES_PASSWORD="$DB_PASSWORD" \
    -v "$DB_VOLUME:/var/lib/postgresql/data" \
    "$DB_IMAGE" >/dev/null
}

wait_for_db() {
  echo -n "Waiting for Postgres"
  for _ in $(seq 1 60); do
    if podman exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
      echo " ready."
      return 0
    fi
    echo -n "."
    sleep 2
  done
  echo
  echo "Error: Postgres did not become ready." >&2
  exit 1
}

start_sonar() {
  if container_running "$SONAR_CONTAINER"; then
    echo "SonarQube already running."
    return
  fi
  if container_exists "$SONAR_CONTAINER"; then
    echo "Resuming SonarQube..."
    podman start "$SONAR_CONTAINER" >/dev/null
    return
  fi
  echo "Creating SonarQube..."
  # The podman VM sets vm.max_map_count below what the embedded Elasticsearch
  # demands, so its bootstrap checks must be skipped or the server never starts.
  podman run -d \
    --name "$SONAR_CONTAINER" \
    --network "$NETWORK" \
    --memory "$SONAR_MEMORY" \
    -p "$SONAR_PORT:9000" \
    -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
    -e SONAR_JDBC_URL="jdbc:postgresql://$DB_CONTAINER:5432/$DB_NAME" \
    -e SONAR_JDBC_USERNAME="$DB_USER" \
    -e SONAR_JDBC_PASSWORD="$DB_PASSWORD" \
    -v "$DATA_VOLUME:/opt/sonarqube/data" \
    -v "$EXT_VOLUME:/opt/sonarqube/extensions" \
    -v "$LOGS_VOLUME:/opt/sonarqube/logs" \
    "$SONAR_IMAGE" >/dev/null
}

wait_for_sonar() {
  local deadline=$((SECONDS + HEALTH_TIMEOUT_SECONDS))
  echo -n "Waiting for SonarQube (first boot takes a minute or two)"
  while ((SECONDS < deadline)); do
    if curl -sf "http://localhost:$SONAR_PORT/api/system/status" 2>/dev/null | grep -q '"status":"UP"'; then
      echo " up."
      return 0
    fi
    if ! container_running "$SONAR_CONTAINER"; then
      echo
      echo "Error: the SonarQube container exited. Last logs:" >&2
      podman logs --tail 30 "$SONAR_CONTAINER" >&2
      exit 1
    fi
    echo -n "."
    sleep 5
  done
  echo
  echo "Error: SonarQube was not healthy after ${HEALTH_TIMEOUT_SECONDS}s." >&2
  echo "Check the logs with: ./scripts/sonarqube.sh logs" >&2
  exit 1
}

cmd_start() {
  ensure_podman
  ensure_network
  start_db
  wait_for_db
  start_sonar
  wait_for_sonar
  echo "SonarQube is ready at http://localhost:$SONAR_PORT"
}

cmd_stop() {
  ensure_podman
  podman stop "$SONAR_CONTAINER" "$DB_CONTAINER" 2>/dev/null || true
  echo "Stopped."
}

cmd_status() {
  ensure_podman
  podman ps -a --filter "name=^${SONAR_CONTAINER}$" --filter "name=^${DB_CONTAINER}$" \
    --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
  echo
  curl -sf "http://localhost:$SONAR_PORT/api/system/status" || echo "Server is not answering on port $SONAR_PORT."
  echo
}

cmd_logs() {
  ensure_podman
  podman logs -f "$SONAR_CONTAINER"
}

cmd_clean() {
  ensure_podman
  podman rm -f "$SONAR_CONTAINER" "$DB_CONTAINER" 2>/dev/null || true
  podman volume rm "$DATA_VOLUME" "$EXT_VOLUME" "$LOGS_VOLUME" "$DB_VOLUME" 2>/dev/null || true
  podman network rm "$NETWORK" 2>/dev/null || true
  echo "Removed containers and volumes."
}

case "${1:-}" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  restart) cmd_stop; cmd_start ;;
  status) cmd_status ;;
  logs) cmd_logs ;;
  clean) cmd_clean ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|logs|clean}" >&2
    exit 1
    ;;
esac
