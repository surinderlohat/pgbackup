#!/usr/bin/env bash
# =============================================================================
# docker/setup-docker-host.sh - Prepare a WSL/Linux host for the Docker example
#
# Usage:
#   sudo ./docker/setup-docker-host.sh --project myapp
# =============================================================================

set -euo pipefail

PROJECT_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project) PROJECT_NAME="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$PROJECT_NAME" ]]; then
    echo "ERROR: --project is required" >&2
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run as root: sudo ./docker/setup-docker-host.sh --project ${PROJECT_NAME}" >&2
    exit 1
fi

if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echo "ERROR: docker compose/docker-compose is required" >&2
    exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
secret_example="${repo_root}/docker/secrets/pg_password.txt.example"
secret_target="${repo_root}/docker/secrets/pg_password.txt"

install -d -m755 /etc/pgbackrest /var/backups/pgbackrest /var/log/pgbackrest
install -d -m700 "$(dirname "${secret_target}")"

if [[ ! -f "${secret_target}" ]]; then
    cp "${secret_example}" "${secret_target}"
    chmod 600 "${secret_target}"
    echo "Created ${secret_target} from example."
    echo "Edit it before starting Docker."
else
    chmod 600 "${secret_target}"
fi

install -d -m750 "/var/backups/pgbackrest/${PROJECT_NAME}"

cat <<EOF
Docker host prepared for project: ${PROJECT_NAME}

Next steps:
  1. Edit the DB password: ${secret_target}
  2. Start PostgreSQL:      ${DOCKER_COMPOSE_CMD} -f docker/docker-compose.yml up -d
  3. Create config:         pgbackup init --project ${PROJECT_NAME} --output /etc/pgbackup/${PROJECT_NAME}.env
  4. Edit config:           /etc/pgbackup/${PROJECT_NAME}.env
EOF
