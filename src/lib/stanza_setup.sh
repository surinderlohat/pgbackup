#!/usr/bin/env bash
# =============================================================================
# lib/stanza_setup.sh — Initialise pgBackRest stanza for a new project
#
# Called once by: pgbackup setup --config /etc/pgbackup/myapp.env
#
# What this does:
#   1. Writes pgBackRest config for this project
#   2. Creates the stanza (pgbackrest stanza-create)
#   3. Verifies PostgreSQL WAL archiving is configured correctly
#   4. Optionally runs a first full backup
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

CONFIG_FILE=""
RUN_FIRST_BACKUP=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)           CONFIG_FILE="$2"; shift 2 ;;
        --run-first-backup) RUN_FIRST_BACKUP=true; shift ;;
        *) log_error "Unknown: $1"; exit 1 ;;
    esac
done

load_config "$CONFIG_FILE"
ensure_dirs
check_deps

START=$(date +%s)

log_info "=========================================="
log_info "pgbackup stanza setup: ${PROJECT_NAME}"
log_info "=========================================="

# --- 1. Write pgBackRest config ---
log_info "[1/4] Writing pgBackRest config → ${PGBACKREST_CONF}"
write_pgbackrest_conf
log_info "      Done"

# --- 2. Check PostgreSQL is reachable ---
log_info "[2/4] Checking PostgreSQL connectivity..."
check_postgres || {
    send_alert "Setup FAILED: Cannot connect to PostgreSQL" \
        "Host: ${PG_HOST}:${PG_PORT}"
    exit 1
}

# --- 3. Create pgBackRest stanza ---
log_info "[3/4] Creating pgBackRest stanza: ${STANZA}"
log_info "      (This configures the repository structure)"

if pgbr stanza-create --log-level-console=info 2>&1 | tee -a "$LOG_FILE"; then
    log_info "      Stanza created OK"
else
    log_error "stanza-create failed — check pgBackRest config and PostgreSQL access"
    exit 1
fi

# --- 4. Check pgBackRest can talk to PostgreSQL ---
log_info "[4/4] Verifying pgBackRest → PostgreSQL connectivity..."
if pgbr check --log-level-console=info 2>&1 | tee -a "$LOG_FILE"; then
    log_info "      Check passed"
else
    log_warn "pgbackrest check failed."
    log_warn "Make sure archive_command is set in postgresql.conf:"
    log_warn ""
    log_warn "  Run: pgbackup wal-setup --config ${CONFIG_FILE}"
    log_warn ""
    log_warn "  Then reload PostgreSQL and re-run: pgbackup setup --config ${CONFIG_FILE}"
    exit 1
fi

log_info "=========================================="
log_info "Stanza setup complete! ($(elapsed_since $START)s)"
log_info ""
log_info "Next steps:"
log_info "  1. Enable timers:    sudo pgbackup enable --config ${CONFIG_FILE}"
log_info "  2. First backup:     sudo -u postgres pgbackup backup --config ${CONFIG_FILE}"
log_info "  3. Check status:     pgbackup status --config ${CONFIG_FILE}"
log_info "=========================================="

# Optional immediate first backup
if [[ "$RUN_FIRST_BACKUP" == true ]]; then
    log_info "Running first full backup now..."
    exec "${SCRIPT_DIR}/full_backup.sh" --config "$CONFIG_FILE"
fi
