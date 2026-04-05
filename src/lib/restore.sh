#!/usr/bin/env bash
# =============================================================================
# lib/restore.sh — Restore PostgreSQL via pgBackRest
#
# Usage:
#   pgbackup restore --config /etc/pgbackup/myapp.env [OPTIONS]
#
# Options:
#   --target-dir  Directory to restore into (required)
#   --pitr        Point-in-time target e.g. "2024-01-15 14:30:00+00"
#   --backup-set  Specific backup label (default: latest)
#   --dry-run     Show what would be done without doing it
#   --delta       Only restore changed files (faster for in-place recovery)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

CONFIG_FILE=""
TARGET_DIR=""
PITR_TARGET=""
BACKUP_SET=""
DRY_RUN=false
DELTA=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)     CONFIG_FILE="$2"; shift 2 ;;
        --target-dir) TARGET_DIR="$2";  shift 2 ;;
        --pitr)       PITR_TARGET="$2"; shift 2 ;;
        --backup-set) BACKUP_SET="$2";  shift 2 ;;
        --dry-run)    DRY_RUN=true;     shift   ;;
        --delta)      DELTA=true;       shift   ;;
        *) log_error "Unknown: $1"; exit 1 ;;
    esac
done

[[ -z "$TARGET_DIR" ]] && { log_error "--target-dir is required"; exit 1; }

load_config "$CONFIG_FILE"
ensure_dirs
check_deps

log_info "=========================================="
log_info "pgbackup restore: ${PROJECT_NAME}"
log_info "=========================================="
[[ "$DRY_RUN" == true ]] && log_warn "DRY RUN MODE"

log_info "Target dir:  $TARGET_DIR"
[[ -n "$PITR_TARGET" ]]  && log_info "PITR target: $PITR_TARGET" \
                          || log_info "PITR target: latest"
[[ -n "$BACKUP_SET" ]]   && log_info "Backup set:  $BACKUP_SET"

# --- Show available backups ---
log_info ""
log_info "Available backups:"
pgbr info --output=text 2>&1 | tee -a "$LOG_FILE"
log_info ""

# Safety check
if [[ -d "$TARGET_DIR" ]] && [[ -n "$(ls -A "$TARGET_DIR" 2>/dev/null)" ]]; then
    if [[ "$DELTA" != true && "$DRY_RUN" != true ]]; then
        log_error "Target directory exists and is not empty: $TARGET_DIR"
        log_error "Use --delta for in-place recovery, or choose an empty directory."
        exit 1
    fi
fi

[[ "$DRY_RUN" == true ]] && {
    log_info "[DRY RUN] Would run pgbackrest restore to: $TARGET_DIR"
    [[ -n "$PITR_TARGET" ]] && log_info "[DRY RUN] Would set recovery target: $PITR_TARGET"
    exit 0
}

mkdir -p "$TARGET_DIR"

# --- Build pgbackrest restore command ---
RESTORE_ARGS=(
    restore
    --pg1-path="$TARGET_DIR"
    --log-level-console=info
)

# Delta restore (only changed blocks — much faster for large DBs)
[[ "$DELTA" == true ]] && RESTORE_ARGS+=(--delta)

# Specific backup set
[[ -n "$BACKUP_SET" ]] && RESTORE_ARGS+=(--set="$BACKUP_SET")

# Point-in-time recovery
if [[ -n "$PITR_TARGET" ]]; then
    RESTORE_ARGS+=(
        --type=time
        --target="$PITR_TARGET"
        --target-action=promote
    )
else
    RESTORE_ARGS+=(
        --type=default     # Restore to end of WAL (latest consistent state)
    )
fi

# --- Run restore ---
START=$(date +%s)
log_info "Starting pgBackRest restore..."

if pgbr "${RESTORE_ARGS[@]}" 2>&1 | tee -a "$LOG_FILE"; then
    DURATION=$(elapsed_since "$START")
    log_info "=========================================="
    log_info "Restore complete in ${DURATION}s"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Review/adjust postgresql.conf in: $TARGET_DIR"
    log_info "  2. Start PostgreSQL:"
    log_info "     pg_ctl -D $TARGET_DIR start"
    log_info "     — or update your service's data_directory"
    log_info "  3. PostgreSQL will replay WAL and promote automatically"
    [[ -n "$PITR_TARGET" ]] && \
    log_info "  4. Verify data at target time: $PITR_TARGET"
    log_info "=========================================="
else
    DURATION=$(elapsed_since "$START")
    log_error "Restore FAILED after ${DURATION}s"
    send_alert "Restore FAILED for ${PROJECT_NAME}" \
        "Target: ${TARGET_DIR}\nPITR: ${PITR_TARGET:-latest}\nCheck logs: ${LOG_FILE}"
    exit 1
fi
