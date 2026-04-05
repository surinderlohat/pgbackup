#!/usr/bin/env bash
# =============================================================================
# install.sh — Install pgbackup v2 (pgBackRest edition) system-wide
#
# Usage:
#   sudo ./install.sh [--prefix /usr/local]
# =============================================================================

set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
PGBACKUP_VERSION="2.0.0"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BIN_DIR="${PREFIX}/bin"
LIB_DIR="${PREFIX}/lib/pgbackup"
SHARE_DIR="${PREFIX}/share/pgbackup"
TEMPLATES_DIR="${SHARE_DIR}/templates"
CONF_DIR="/etc/pgbackup"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${GREEN}▶${RESET} $*"; }
success() { echo -e "${GREEN}✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET}  $*"; }
error()   { echo -e "${RED}✗${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

[[ $EUID -ne 0 ]] && { error "Run as root: sudo ./install.sh"; exit 1; }

header "pgbackup v${PGBACKUP_VERSION} (pgBackRest edition) — Installer"
echo "  Prefix:  $PREFIX"
echo "  Configs: $CONF_DIR"

# --- Check pgBackRest ---
header "Checking pgBackRest..."
if command -v pgbackrest &>/dev/null; then
    PBVER=$(pgbackrest version 2>/dev/null | head -1)
    success "Found: $PBVER"
else
    warn "pgBackRest not found. Install it first:"
    echo ""
    echo "  Ubuntu/Debian:"
    echo "    sudo apt install pgbackrest"
    echo ""
    echo "  RHEL/Rocky/AlmaLinux:"
    echo "    sudo dnf install pgbackrest"
    echo ""
    echo "  From source / latest:"
    echo "    https://pgbackrest.org/user-guide.html#installation"
    echo ""
    read -r -p "Continue installation anyway? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 1
fi

# --- Check other deps ---
header "Checking other dependencies..."
for cmd in psql gzip; do
    command -v "$cmd" &>/dev/null \
        && success "$cmd" \
        || warn "$cmd not found (install postgresql-client)"
done

# --- Install ---
header "Installing files..."
install -d -m755 "$BIN_DIR" "$LIB_DIR" "$TEMPLATES_DIR"
install -d -m750 "$CONF_DIR"
chown root:postgres "$CONF_DIR" 2>/dev/null || true

install -m755 "${SRC}/src/pgbackup"               "${BIN_DIR}/pgbackup"

for f in common.sh full_backup.sh restore.sh check_backup.sh \
          stanza_setup.sh systemd_install.sh; do
    if [[ -f "${SRC}/src/lib/${f}" ]]; then
        install -m755 "${SRC}/src/lib/${f}" "${LIB_DIR}/${f}"
        success "lib/${f}"
    else
        warn "Missing: src/lib/${f}"
    fi
done

install -m644 "${SRC}/templates/backup.env.template" \
              "${TEMPLATES_DIR}/backup.env.template"
success "Config template"

# --- Verify ---
header "Verifying..."
if pgbackup version &>/dev/null; then
    success "$(pgbackup version)"
else
    error "Verification failed"
    exit 1
fi

# --- Done ---
header "Done! 🎉"
cat <<EOF

pgbackup is installed. To set up your first project:

  ${BOLD}1. Create config${RESET}
     pgbackup init --project myapp --output /etc/pgbackup/myapp.env
     nano /etc/pgbackup/myapp.env

  ${BOLD}2. Configure WAL archiving${RESET}
     pgbackup wal-setup --config /etc/pgbackup/myapp.env
     # add lines to postgresql.conf, then:
     # SELECT pg_reload_conf();

  ${BOLD}3. Initialise pgBackRest stanza${RESET}
     sudo pgbackup setup --config /etc/pgbackup/myapp.env

  ${BOLD}4. Enable automated scheduling${RESET}
     sudo pgbackup enable --config /etc/pgbackup/myapp.env

  ${BOLD}5. First backup + verify${RESET}
     sudo -u postgres pgbackup backup --config /etc/pgbackup/myapp.env
     pgbackup status --config /etc/pgbackup/myapp.env
     pgbackup check  --config /etc/pgbackup/myapp.env

  ${BOLD}For a second project — repeat steps 1-5 with a new name!${RESET}

EOF
