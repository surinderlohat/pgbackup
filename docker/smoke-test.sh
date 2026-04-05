#!/usr/bin/env bash
# =============================================================================
# docker/smoke-test.sh - End-to-end smoke test for the Docker example on WSL
#
# Assumes:
#   - pgbackup is installed on the Linux host
#   - pgbackrest and psql are installed
#   - docker/setup-docker-host.sh has been run
# =============================================================================

set -euo pipefail

PROJECT_NAME="${PROJECT_NAME:-myapp}"
CONFIG_FILE="${CONFIG_FILE:-/etc/pgbackup/${PROJECT_NAME}.env}"
COMPOSE_FILE="${COMPOSE_FILE:-docker/docker-compose.yml}"
RESTORE_DIR="${RESTORE_DIR:-/tmp/${PROJECT_NAME}-restore}"
DB_PASSWORD_FILE="${DB_PASSWORD_FILE:-docker/secrets/pg_password.txt}"

if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE=(docker-compose)
else
    echo "ERROR: docker compose/docker-compose is required" >&2
    exit 1
fi

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "ERROR: Config not found: ${CONFIG_FILE}" >&2
    exit 1
fi

if [[ ! -f "${DB_PASSWORD_FILE}" ]]; then
    echo "ERROR: Secret not found: ${DB_PASSWORD_FILE}" >&2
    exit 1
fi

export PGPASSWORD
PGPASSWORD="$(<"${DB_PASSWORD_FILE}")"

echo "[1/8] Starting PostgreSQL container"
"${DOCKER_COMPOSE[@]}" -f "${COMPOSE_FILE}" up -d

echo "[2/8] Waiting for PostgreSQL"
for _ in $(seq 1 30); do
    if psql -h 127.0.0.1 -p 5432 -U postgres -d myapp_production -c "SELECT 1" -q --tuples-only >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

psql -h 127.0.0.1 -p 5432 -U postgres -d myapp_production -c "SELECT 1" -q --tuples-only >/dev/null

echo "[3/8] Creating sample table"
psql -h 127.0.0.1 -p 5432 -U postgres -d myapp_production <<'SQL'
CREATE TABLE IF NOT EXISTS smoke_test (
    id integer PRIMARY KEY,
    note text NOT NULL
);
INSERT INTO smoke_test (id, note)
VALUES (1, 'backup smoke test')
ON CONFLICT (id) DO UPDATE SET note = EXCLUDED.note;
SQL

echo "[4/8] Generating pgBackRest config and stanza"
sudo pgbackup setup --config "${CONFIG_FILE}"

echo "[5/8] Running a full backup"
sudo -u postgres pgbackup backup --config "${CONFIG_FILE}" --type full

echo "[6/8] Running health checks"
pgbackup check --config "${CONFIG_FILE}"

echo "[7/8] Restoring into ${RESTORE_DIR}"
rm -rf "${RESTORE_DIR}"
pgbackup restore --config "${CONFIG_FILE}" --target-dir "${RESTORE_DIR}"

echo "[8/8] Smoke test complete"
pgbackup status --config "${CONFIG_FILE}"
echo "Restore files written to ${RESTORE_DIR}"
