#!/bin/bash
set -euo pipefail

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${COMMON_DIR}/.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/config/toolkit.conf"

find_project_root() {
    local start_dir="${1:-$(pwd)}"
    local dir

    dir="$(cd "${start_dir}" && pwd)"

    while [ "${dir}" != "/" ]; do
        if [ -f "${dir}/config/toolkit.conf" ] && [ -d "${dir}/lib" ]; then
            printf '%s\n' "${dir}"
            return 0
        fi
        dir="$(dirname "${dir}")"
    done

    return 1
}

load_config() {
    local root="${1:-${PROJECT_ROOT}}"
    local config_file="${root}/config/toolkit.conf"

    if [ ! -f "${config_file}" ]; then
        printf 'Error: config file not found: %s\n' "${config_file}" >&2
        return 1
    fi

    # shellcheck source=/dev/null
    . "${config_file}"
}

create_needed_folders() {
    local root="${1:-${PROJECT_ROOT}}"

    mkdir -p \
        "${root}/${REPORTS_DIR:-reports}" \
        "${root}/${LOGS_DIR:-logs}" \
        "${root}/${BACKUP_DIR:-backups}" \
        "${root}/samples"
}

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_action() {
    local level="${1:-INFO}"
    local module="${2:-core}"
    local message="${3:-}"
    local log_dir="${PROJECT_ROOT}/${LOGS_DIR:-logs}"

    mkdir -p "${log_dir}"
    printf '[%s] [%s] [%s] %s\n' "$(timestamp)" "${level}" "${module}" "${message}" >> "${log_dir}/toolkit.log"
}

log_alert() {
    local message="${1:-}"
    local log_dir="${PROJECT_ROOT}/${LOGS_DIR:-logs}"

    mkdir -p "${log_dir}"
    printf '[%s] [ALERT] %s\n' "$(timestamp)" "${message}" >> "${log_dir}/alerts.log"
    log_action "ALERT" "alerts" "${message}"
}

_color() {
    local code="${1}"
    shift

    if [ -t 1 ]; then
        printf '\033[%sm%s\033[0m\n' "${code}" "$*"
    else
        printf '%s\n' "$*"
    fi
}

print_success() {
    _color "32" "SUCCESS: $*"
}

print_warning() {
    _color "33" "WARNING: $*"
}

print_error() {
    _color "31" "ERROR: $*" >&2
}

print_info() {
    _color "34" "INFO: $*"
}

require_root() {
    local module="${1:-core}"

    if [ "$(id -u)" -ne 0 ]; then
        print_error "${module} requires root privileges."
        log_action "ERROR" "${module}" "Root privileges required."
        return 1
    fi
}

confirm_action() {
    local message="${1:-Are you sure?}"
    local assume_yes="${2:-false}"
    local answer

    if [ "${assume_yes}" = "true" ] || [ "${assume_yes}" = "yes" ]; then
        return 0
    fi

    printf '%s [y/N]: ' "${message}"
    read -r answer

    case "${answer}" in
        y|Y|yes|YES)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

command_exists() {
    command -v "${1:-}" >/dev/null 2>&1
}

send_email_alert() {
    local subject="${1:-Sysadmin Toolkit Alert}"
    local message="${2:-}"

    if [ "${ENABLE_EMAIL_ALERTS:-false}" != "true" ]; then
        return 0
    fi

    if ! command_exists mail; then
        print_warning "Email alerts are enabled, but the mail command is not installed."
        log_action "WARNING" "email" "mail command not found; alert not sent."
        return 1
    fi

    printf '%s\n' "${message}" | mail -s "${subject}" "${EMAIL_RECIPIENT:-admin@example.com}"
    log_action "INFO" "email" "Email alert sent to ${EMAIL_RECIPIENT:-admin@example.com}: ${subject}"
}

show_common_help() {
    cat <<'EOF'
common.sh

Shared helper library for sysadmin-toolkit.

Usage:
  source lib/common.sh
  ./lib/common.sh -h|--help

This file provides configuration loading, folder setup, logging, colored output,
root checks, confirmation prompts, command checks, and optional email alerts.
EOF
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-}" in
        -h|--help|"")
            show_common_help
            exit 0
            ;;
        *)
            show_common_help
            exit 1
            ;;
    esac
fi

load_config "${PROJECT_ROOT}"
create_needed_folders "${PROJECT_ROOT}"
