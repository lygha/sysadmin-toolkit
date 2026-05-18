#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"

show_help() {
    cat <<'EOF'
demo.sh

Usage:
  ./demo.sh
  ./demo.sh -h|--help

Runs a safe, non-destructive end-to-end demonstration of sysadmin-toolkit.
The demo intentionally avoids root-only user creation/deletion and protected
system log analysis commands.
EOF
}

section() {
    printf '\n'
    printf '============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}

run_step() {
    printf '\n$ %s\n' "$*"
    "$@"
}

refresh_sample_data() {
    mkdir -p "${PROJECT_ROOT}/samples/test-data/docs"

    cat > "${PROJECT_ROOT}/samples/test-data/notes.txt" <<'EOF'
This is safe sample data for testing sysadmin-toolkit backups.
EOF

    cat > "${PROJECT_ROOT}/samples/test-data/config-example.txt" <<'EOF'
app_name=sysadmin-toolkit-demo
environment=sample
owner=student
EOF

    cat > "${PROJECT_ROOT}/samples/test-data/docs/readme.txt" <<'EOF'
Sample nested file for backup and restore testing.
EOF
}

show_root_commands() {
    cat <<'EOF'
Root-required log analysis commands for the instructor:

  sudo ./sysadmin.sh logs failed-logins 7
  sudo ./sysadmin.sh logs successful-logins 7
  sudo ./sysadmin.sh logs errors 7
  sudo ./sysadmin.sh logs top-ips
  sudo ./sysadmin.sh logs summary

Root-required user management commands not run by this demo:

  sudo ./sysadmin.sh users add-bulk ./samples/users.csv
  sudo ./sysadmin.sh users delete testuser1 --archive-home
  sudo ./sysadmin.sh users audit
EOF
}

main() {
    local newest_full=""

    if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
        show_help
        return 0
    fi

    cd "${PROJECT_ROOT}"

    section "Preparing Demo"
    chmod +x sysadmin.sh demo.sh modules/*.sh
    mkdir -p reports logs backups samples
    rm -rf restore-demo
    refresh_sample_data
    printf 'Project root: %s\n' "${PROJECT_ROOT}"

    section "Toolkit Help"
    run_step ./sysadmin.sh --help

    section "System Monitoring"
    run_step ./sysadmin.sh monitor cpu
    run_step ./sysadmin.sh monitor mem
    run_step ./sysadmin.sh monitor disk

    section "Backup Automation"
    run_step ./sysadmin.sh backup full ./samples/test-data ./backups
    run_step ./sysadmin.sh backup incr ./samples/test-data ./backups
    run_step ./sysadmin.sh backup list ./backups

    newest_full="$(find ./backups -maxdepth 1 -type f -name 'full-*.tar.gz' | sort | tail -n 1 || true)"
    if [ -n "${newest_full}" ]; then
        run_step ./sysadmin.sh backup verify "${newest_full}"
        run_step ./sysadmin.sh backup restore "${newest_full}" ./restore-demo -y
    else
        printf 'No full backup archive found to verify or restore.\n'
    fi

    section "User And Permission Checks"
    run_step ./sysadmin.sh users list
    run_step ./sysadmin.sh users perms ./samples

    section "Root-only Log Analysis Commands"
    show_root_commands

    section "Generated Reports"
    if [ -d reports ]; then
        ls -lh reports
    else
        printf 'No reports directory found.\n'
    fi

    section "Toolkit Logs"
    if [ -f logs/toolkit.log ]; then
        tail -n 20 logs/toolkit.log
    else
        printf 'logs/toolkit.log does not exist yet.\n'
    fi

    if [ -f logs/backup.log ]; then
        printf '\nLast backup log entries:\n'
        tail -n 20 logs/backup.log
    else
        printf '\nlogs/backup.log does not exist yet.\n'
    fi

    section "Demo Complete"
    printf 'SUCCESS: Safe sysadmin-toolkit demo completed.\n'
}

main "$@"
