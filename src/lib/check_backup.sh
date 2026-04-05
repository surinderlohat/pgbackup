#!/usr/bin/env bash
# =============================================================================
# lib/check_backup.sh — Health check using pgBackRest
#
# Usage:
#   pgbackup check --config /etc/pgbackup/myapp.env [--alert-on-warn]
#
# Checks:
#   1. pgBackRest installed and version OK
#   2. PostgreSQL connectivity
#   3. WAL archiving working (pgbackrest check)
#   4. Latest backup recency
#   5. Repository integrity (pgbackrest verify)
#   6. Disk / storage space
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

CONFIG_FILE=""
ALERT_ON_WARN=false
ISSUES=()
WARNS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)        CONFIG_FILE="$2"; shift 2 ;;
        --alert-on-warn) ALERT_ON_WARN=true; shift ;;
        *) log_error "Unknown: $1"; exit 1 ;;
    esac
done

load_config "$CONFIG_FILE"
ensure_dirs

ok()   { log_info "  ✓ $*"; }
warn() { log_warn "  ⚠ $*"; WARNS+=("$*"); }
fail() { log_error "  ✗ $*"; ISSUES+=("$*"); }

log_info "=========================================="
log_info "pgbackup health check: ${PROJECT_NAME}"
log_info "=========================================="

# --- 1. pgBackRest version ---
log_info "[1] pgBackRest installation"
if command -v pgbackrest &>/dev/null; then
    PBVER=$(pgbackrest version 2>/dev/null | head -1 || echo "unknown")
    ok "$PBVER"
else
    fail "pgbackrest not found in PATH"
fi

# --- 2. PostgreSQL connectivity ---
log_info "[2] PostgreSQL connectivity"
if psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" \
        -d "${PG_DATABASE:-postgres}" -c "SELECT 1" \
        -q --tuples-only > /dev/null 2>&1; then
    ok "Connected to ${PG_HOST}:${PG_PORT}"
else
    fail "Cannot connect to PostgreSQL at ${PG_HOST}:${PG_PORT}"
fi

# --- 3. pgBackRest check (WAL archiving) ---
log_info "[3] WAL archiving (pgbackrest check)"
CHECK_OUT=$(pgbr check 2>&1 || true)
if echo "$CHECK_OUT" | grep -qi "error\|fatal"; then
    fail "pgbackrest check reported errors — WAL archiving may be broken"
    echo "$CHECK_OUT" | grep -i "error\|fatal" | while read -r line; do
        log_error "    $line"
    done
else
    ok "WAL archiving OK"
fi

# --- 4. Backup recency ---
log_info "[4] Backup recency"
INFO_JSON=$(pgbr info --output=json 2>/dev/null || echo "[]")

if command -v python3 &>/dev/null; then
    LATEST_BACKUP=$(python3 -c "
import json, sys, datetime
data = json.loads('''${INFO_JSON}''')
backups = []
for stanza in data:
    backups.extend(stanza.get('backup', []))
if not backups:
    print('NONE')
    sys.exit(0)
latest = sorted(backups, key=lambda b: b['timestamp']['stop'])[-1]
stop_ts = latest['timestamp']['stop']
age_h = (datetime.datetime.now().timestamp() - stop_ts) / 3600
btype = latest['type']
label = latest['label']
print(f'{label} ({btype}) {age_h:.1f}h ago')
if age_h > 26:
    print('STALE')
" 2>/dev/null || echo "PARSE_ERROR")

    if echo "$LATEST_BACKUP" | grep -q "NONE"; then
        fail "No backups found in repository"
    elif echo "$LATEST_BACKUP" | grep -q "STALE"; then
        warn "Latest backup is more than 26h old: $LATEST_BACKUP"
    elif echo "$LATEST_BACKUP" | grep -q "PARSE_ERROR"; then
        warn "Could not parse backup info — check manually: pgbackup status"
    else
        ok "Latest: $LATEST_BACKUP"
    fi
else
    # Fallback without python3
    pgbr info --output=text 2>&1 | grep -E "label|timestamp" | head -4 \
        | while read -r line; do log_info "    $line"; done
    warn "python3 not found — skipping age calculation"
fi

# --- 5. Repository integrity ---
log_info "[5] Repository integrity (pgbackrest verify)"
# verify can be slow on large repos; run with timeout
VERIFY_OUT=$(timeout 120 pgbr verify 2>&1 || true)
if echo "$VERIFY_OUT" | grep -qi "error\|invalid\|missing"; then
    fail "Repository integrity check found issues"
    echo "$VERIFY_OUT" | grep -i "error\|invalid\|missing" | while read -r line; do
        log_error "    $line"
    done
else
    ok "Repository integrity OK"
fi

# --- 6. Storage space ---
log_info "[6] Storage space"
if [[ "${REPO_TYPE:-posix}" == "posix" ]]; then
    AVAIL_GB=$(df -BG "$REPO_PATH" 2>/dev/null | awk 'NR==2 {gsub("G",""); print $4}' || echo "0")
    USED_PCT=$(df "$REPO_PATH" 2>/dev/null | awk 'NR==2 {gsub("%",""); print $5}' || echo "?")
    log_info "  Available: ${AVAIL_GB}GB (${USED_PCT}% used)"
    if (( AVAIL_GB < 5 )); then
        fail "Critical: less than 5GB free on repository"
    elif (( AVAIL_GB < 20 )); then
        warn "Low disk space: only ${AVAIL_GB}GB free"
    else
        ok "Disk space OK: ${AVAIL_GB}GB free"
    fi
else
    ok "Remote repository (${REPO_TYPE}) — skipping local disk check"
fi

# --- Summary ---
log_info ""
log_info "=========================================="
TOTAL_ISSUES=$(( ${#ISSUES[@]} + ${#WARNS[@]} ))

if [[ ${#ISSUES[@]} -eq 0 && ${#WARNS[@]} -eq 0 ]]; then
    log_info "✓ All checks passed"
    log_info "=========================================="
    exit 0
fi

if [[ ${#ISSUES[@]} -gt 0 ]]; then
    log_error "✗ ${#ISSUES[@]} failure(s):"
    for i in "${ISSUES[@]}"; do log_error "  - $i"; done
fi

if [[ ${#WARNS[@]} -gt 0 ]]; then
    log_warn "⚠ ${#WARNS[@]} warning(s):"
    for w in "${WARNS[@]}"; do log_warn "  - $w"; done
fi

log_info "=========================================="

ALERT_BODY=$(printf '%s\n' "${ISSUES[@]+"${ISSUES[@]}"}" "${WARNS[@]+"${WARNS[@]}"}")
if [[ ${#ISSUES[@]} -gt 0 ]]; then
    send_alert "Backup health check FAILED: ${PROJECT_NAME}" "$ALERT_BODY"
    exit 1
elif [[ "$ALERT_ON_WARN" == true && ${#WARNS[@]} -gt 0 ]]; then
    send_alert "Backup health check WARNING: ${PROJECT_NAME}" "$ALERT_BODY"
    exit 1
fi

exit 0
