#!/usr/bin/env bash
# =============================================================================
# lib/systemd_install.sh — Install/remove systemd units for a project
# Sourced by pgbackup CLI — not executed directly.
# =============================================================================

systemd_install() {
    local project="$1"
    local config_file="$2"
    local full_time="${FULL_BACKUP_SCHEDULE:-02:00}"
    local diff_time="${DIFF_BACKUP_SCHEDULE:-12:00}"
    local prefix="pgbackup-${project}"

    echo "Installing systemd units for: $project"

    # Full backup service
    cat > "/etc/systemd/system/${prefix}-full.service" <<EOF
[Unit]
Description=pgbackup Full Backup (${project})
After=network.target

[Service]
Type=oneshot
User=postgres
Group=postgres
ExecStart=pgbackup backup --config ${config_file} --type full
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${prefix}-full
TimeoutStartSec=6h
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF

    # Full backup timer
    cat > "/etc/systemd/system/${prefix}-full.timer" <<EOF
[Unit]
Description=pgbackup Daily Full Backup (${project})

[Timer]
OnCalendar=*-*-* ${full_time}:00
Persistent=true
RandomizedDelaySec=5min
Unit=${prefix}-full.service

[Install]
WantedBy=timers.target
EOF

    # Differential backup service
    cat > "/etc/systemd/system/${prefix}-diff.service" <<EOF
[Unit]
Description=pgbackup Differential Backup (${project})
After=network.target

[Service]
Type=oneshot
User=postgres
Group=postgres
ExecStart=pgbackup backup --config ${config_file} --type diff
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${prefix}-diff
TimeoutStartSec=4h
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF

    # Differential backup timer (midday, between full backups)
    cat > "/etc/systemd/system/${prefix}-diff.timer" <<EOF
[Unit]
Description=pgbackup Differential Backup Timer (${project})

[Timer]
OnCalendar=*-*-* ${diff_time}:00
Persistent=true
RandomizedDelaySec=5min
Unit=${prefix}-diff.service

[Install]
WantedBy=timers.target
EOF

    # Health check service
    cat > "/etc/systemd/system/${prefix}-check.service" <<EOF
[Unit]
Description=pgbackup Health Check (${project})
After=network.target

[Service]
Type=oneshot
User=postgres
ExecStart=pgbackup check --config ${config_file} --alert-on-warn
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${prefix}-check
EOF

    # Health check timer (every 6h)
    cat > "/etc/systemd/system/${prefix}-check.timer" <<EOF
[Unit]
Description=pgbackup Health Check Timer (${project})

[Timer]
OnCalendar=*-*-* 00,06,12,18:00:00
Persistent=true
Unit=${prefix}-check.service

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now "${prefix}-full.timer"
    systemctl enable --now "${prefix}-diff.timer"
    systemctl enable --now "${prefix}-check.timer"

    echo ""
    echo "✓ Systemd timers installed and enabled:"
    echo "  ${prefix}-full.timer  → daily full at ${full_time}"
    echo "  ${prefix}-diff.timer  → differential at ${diff_time}"
    echo "  ${prefix}-check.timer → health check every 6h"
    echo ""
    echo "View status:  systemctl list-timers 'pgbackup-${project}*'"
    echo "View logs:    journalctl -u ${prefix}-full.service -f"
}

systemd_uninstall() {
    local project="$1"
    local prefix="pgbackup-${project}"

    echo "Removing systemd units for: $project"
    for unit in full.timer full.service diff.timer diff.service check.timer check.service; do
        local name="${prefix}-${unit}"
        systemctl stop    "$name" 2>/dev/null || true
        systemctl disable "$name" 2>/dev/null || true
        rm -f "/etc/systemd/system/${name}"
        echo "  Removed: $name"
    done
    systemctl daemon-reload
    echo "✓ Done"
}
