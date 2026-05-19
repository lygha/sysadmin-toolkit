#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

show_help() {
    cat <<'EOF'
====================================
 Linux SysAdmin Toolkit
 Operating Systems Project
====================================

Usage:
  ./sysadmin.sh <module> <command> [arguments]
  ./sysadmin.sh -h|--help

Modules:
  monitor    System monitoring commands
  users      User administration commands
  backup     Backup commands
  logs       Log inspection commands

Dispatcher examples:
  ./sysadmin.sh monitor cpu
  ./sysadmin.sh users list
  ./sysadmin.sh backup full src dest
  ./sysadmin.sh logs failed-logins 7

Note:
  Some commands require sudo because they manage Linux users or read
  protected system logs.
EOF
}

dispatch_module() {
    local module="${1}"
    shift
    local module_script="${PROJECT_ROOT}/modules/${module}.sh"

    case "${module}" in
        monitor|users|backup|logs)
            "${module_script}" "$@"
            ;;
        *)
            print_error "Unknown module: ${module}"
            show_help
            return 1
            ;;
    esac
}

main() {
    if [ "$#" -eq 0 ]; then
        show_help
        return 0
    fi

    case "${1}" in
        -h|--help)
            show_help
            return 0
            ;;
        monitor|users|backup|logs)
            dispatch_module "$@"
            ;;
        *)
            print_error "Unknown module: ${1}"
            show_help
            return 1
            ;;
    esac
}

main "$@"
