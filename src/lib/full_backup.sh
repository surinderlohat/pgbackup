#!/usr/bin/env bash
# =============================================================================
# lib/full_backup.sh — Full base backup via pgBackRest
#
# Usage:
#   pgbackup backup --config /etc/pgbackup/myapp.env [--type full|diff|incr]
#
# pgBackRest backup types:
#   full  — complete backup (default, runs on schedule)
#   diff  — changes since last full (faster, runs midday)
#   incr  — changes since last backup of any type (smallest/fastest)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

CONFIG_FILE=""
BACKUP_TYPE="full"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --type)   BACKUP_TYPE="$2"; shift 2 ;;
        *) log_error "Unknown: $1"; exit 1 ;;
    esac
done

load_config "$CONFIG_FILE"
ensure_dirs
check_deps
acquire_lock

START=$(date +%s)

log_info "=========================================="
log_info "pgbackup backup: ${PROJECT_NAME} [${BACKUP_TYPE}]"
log_info "=========================================="

# --- Pre-flight ---
check_postgres || {
    send_alert "Backup FAILED: Cannot connect to PostgreSQL" \
        "Project: ${PROJECT_NAME}, Type: ${BACKUP_TYPE}"
    exit 1
}

# --- Run pgBackRest backup ---
log_info "Running pgbackrest backup --type=${BACKUP_TYPE}..."
log_info "  Stanza:      ${STANZA}"
log_info "  Repo:        ${REPO_TYPE}${REPO_PATH:+ → $REPO_PATH}${REPO_S3_BUCKET:+ → s3://$REPO_S3_BUCKET}"
log_info "  Compress:    ${COMPRESS_TYPE:-lz4}"
log_info "  Parallel:    ${PARALLEL_JOBS:-2} jobs"

if pgbr backup \
    --type="$BACKUP_TYPE" \
    --log-level-console=info \
    2>&1 | tee -a "$LOG_FILE"; then

    DURATION=$(elapsed_since "$START")
    log_info "Backup completed successfully in ${DURATION}s"

    # Show backup info
    log_info "Current backup set:"
    pgbr info --output=text 2>&1 | tee -a "$LOG_FILE"

else
    DURATION=$(elapsed_since "$START")
    log_error "pgBackRest backup FAILED after ${DURATION}s"
    send_alert "Backup FAILED for ${PROJECT_NAME} [${BACKUP_TYPE}]" \
        "Duration: ${DURATION}s\nCheck logs: ${LOG_FILE}\nRun: pgbackup status --config ${CONFIG_FILE}"
    exit 1
fi

log_info "=========================================="
log_info "Done. Total time: ${DURATION}s"
log_info "=========================================="
