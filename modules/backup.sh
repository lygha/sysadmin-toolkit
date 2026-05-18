#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"

BACKUP_LOG="${PROJECT_ROOT}/${LOGS_DIR:-logs}/backup.log"

show_help() {
    cat <<'EOF'
backup module

Usage:
  ./modules/backup.sh <command> [arguments]
  ./modules/backup.sh -h|--help

Commands:
  full <src> <dest>                 Create a full tar.gz backup
  incr <src> <dest>                 Create an incremental rsync snapshot
  list <dest>                       List backups in a destination
  restore <archive> <target> [-y]   Restore a full backup archive
  verify <archive>                  Verify archive integrity and checksum
  rotate <dest> <N> [-y]            Keep only N newest full backups

Examples:
  ./sysadmin.sh backup full ./samples/test-data ./backups
  ./sysadmin.sh backup incr ./samples/test-data ./backups
  ./sysadmin.sh backup list ./backups
  ./sysadmin.sh backup verify ./backups/full-test-data-20260101-030000.tar.gz
EOF
}

usage_error() {
    print_error "$1"
    show_help
    return 1
}

backup_timestamp() {
    date '+%Y%m%d-%H%M%S'
}

archive_basename() {
    basename "$1" | tr ' /' '__'
}

human_size() {
    if [ -e "$1" ]; then
        du -sh "$1" 2>/dev/null | awk '{ print $1 }'
    else
        printf '0\n'
    fi
}

log_backup_operation() {
    local operation="$1"
    local start_time="$2"
    local end_time="$3"
    local source_path="$4"
    local destination_path="$5"
    local size="$6"
    local outcome="$7"

    mkdir -p "$(dirname "${BACKUP_LOG}")"
    {
        printf '[%s] operation=%s\n' "${end_time}" "${operation}"
        printf '  start=%s\n' "${start_time}"
        printf '  end=%s\n' "${end_time}"
        printf '  source=%s\n' "${source_path}"
        printf '  destination=%s\n' "${destination_path}"
        printf '  size=%s\n' "${size}"
        printf '  outcome=%s\n' "${outcome}"
    } >> "${BACKUP_LOG}"
}

is_yes_flag() {
    case "${1:-}" in
        -y|--yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_positive_integer() {
    case "${1:-}" in
        ''|*[!0-9]*)
            return 1
            ;;
        *)
            [ "$1" -gt 0 ]
            ;;
    esac
}

make_checksum() {
    local archive="$1"
    local archive_dir archive_file

    archive_dir="$(cd "$(dirname "${archive}")" && pwd)"
    archive_file="$(basename "${archive}")"
    (cd "${archive_dir}" && sha256sum "${archive_file}") > "${archive}.sha256"
}

create_full_backup() {
    local src="${1:-}"
    local dest="${2:-}"
    local start_time end_time base archive size outcome parent item

    if [ -z "${src}" ] || [ -z "${dest}" ]; then
        usage_error "full requires <src> and <dest>."
        return 1
    fi

    start_time="$(timestamp)"
    outcome="failure"

    if [ ! -e "${src}" ]; then
        end_time="$(timestamp)"
        log_backup_operation "full" "${start_time}" "${end_time}" "${src}" "${dest}" "0" "${outcome}"
        print_error "Source does not exist: ${src}"
        return 1
    fi

    command_exists tar || { print_error "tar is required for full backups."; return 1; }
    command_exists gzip || { print_error "gzip is required for full backups."; return 1; }
    command_exists sha256sum || { print_error "sha256sum is required for checksums."; return 1; }

    mkdir -p "${dest}"
    base="$(archive_basename "${src}")"
    archive="${dest}/full-${base}-$(backup_timestamp).tar.gz"
    parent="$(cd "$(dirname "${src}")" && pwd)"
    item="$(basename "${src}")"

    log_action "INFO" "backup" "Full backup started: ${src} -> ${archive}"

    if tar -czf "${archive}" -C "${parent}" "${item}"; then
        make_checksum "${archive}"
        size="$(human_size "${archive}")"
        outcome="success"
        end_time="$(timestamp)"
        log_backup_operation "full" "${start_time}" "${end_time}" "${src}" "${archive}" "${size}" "${outcome}"
        log_action "INFO" "backup" "Full backup completed: ${archive}"
        print_success "Full backup created: ${archive}"
        printf 'Checksum: %s.sha256\n' "${archive}"
    else
        size="0"
        end_time="$(timestamp)"
        log_backup_operation "full" "${start_time}" "${end_time}" "${src}" "${archive}" "${size}" "${outcome}"
        log_action "ERROR" "backup" "Full backup failed: ${src}"
        print_error "Full backup failed."
        return 1
    fi
}

absolute_path_for_existing_or_parent() {
    local path="$1"

    if [ -e "${path}" ]; then
        cd "${path}" 2>/dev/null && pwd && return 0
    fi

    mkdir -p "${path}"
    cd "${path}" && pwd
}

create_incremental_backup() {
    local src="${1:-}"
    local dest="${2:-}"
    local start_time end_time base snapshot latest latest_abs size outcome src_arg

    if [ -z "${src}" ] || [ -z "${dest}" ]; then
        usage_error "incr requires <src> and <dest>."
        return 1
    fi

    start_time="$(timestamp)"
    outcome="failure"

    if [ ! -e "${src}" ]; then
        end_time="$(timestamp)"
        log_backup_operation "incr" "${start_time}" "${end_time}" "${src}" "${dest}" "0" "${outcome}"
        print_error "Source does not exist: ${src}"
        return 1
    fi

    if ! command_exists rsync; then
        end_time="$(timestamp)"
        log_backup_operation "incr" "${start_time}" "${end_time}" "${src}" "${dest}" "0" "${outcome}"
        print_error "rsync is required for incremental backups. Install it with: sudo apt install rsync"
        return 1
    fi

    mkdir -p "${dest}"
    base="$(archive_basename "${src}")"
    snapshot="${dest}/incr-${base}-$(backup_timestamp)"
    latest="${dest}/latest-${base}"
    mkdir -p "${snapshot}"

    log_action "INFO" "backup" "Incremental backup started: ${src} -> ${snapshot}"

    if [ -d "${src}" ]; then
        src_arg="${src%/}/"
    else
        src_arg="${src}"
    fi

    if [ -d "${latest}" ]; then
        latest_abs="$(cd "${latest}" && pwd)"
        if rsync -a --delete --link-dest="${latest_abs}" "${src_arg}" "${snapshot}/"; then
            :
        else
            end_time="$(timestamp)"
            log_backup_operation "incr" "${start_time}" "${end_time}" "${src}" "${snapshot}" "0" "${outcome}"
            log_action "ERROR" "backup" "Incremental backup failed: ${src}"
            print_error "Incremental backup failed."
            return 1
        fi
    else
        if rsync -a "${src_arg}" "${snapshot}/"; then
            :
        else
            end_time="$(timestamp)"
            log_backup_operation "incr" "${start_time}" "${end_time}" "${src}" "${snapshot}" "0" "${outcome}"
            log_action "ERROR" "backup" "Incremental backup failed: ${src}"
            print_error "Incremental backup failed."
            return 1
        fi
    fi

    rm -rf "${latest}"
    mkdir -p "${latest}"
    rsync -a --delete "${snapshot}/" "${latest}/"

    size="$(human_size "${snapshot}")"
    outcome="success"
    end_time="$(timestamp)"
    log_backup_operation "incr" "${start_time}" "${end_time}" "${src}" "${snapshot}" "${size}" "${outcome}"
    log_action "INFO" "backup" "Incremental backup completed: ${snapshot}"
    print_success "Incremental backup created: ${snapshot}"
    print_info "Latest snapshot updated: ${latest}"
}

detect_backup_date() {
    local name="$1"

    printf '%s\n' "${name}" | awk '{
        if (match($0, /[0-9]{8}-[0-9]{6}/)) {
            print substr($0, RSTART, RLENGTH)
        } else {
            print "unknown"
        }
    }'
}

list_backups() {
    local dest="${1:-}"
    local found path name type size date_value start_time end_time

    if [ -z "${dest}" ]; then
        usage_error "list requires <dest>."
        return 1
    fi

    start_time="$(timestamp)"

    if [ ! -d "${dest}" ]; then
        end_time="$(timestamp)"
        log_backup_operation "list" "${start_time}" "${end_time}" "${dest}" "${dest}" "0" "failure"
        print_warning "Backup destination does not exist: ${dest}"
        return 0
    fi

    log_action "INFO" "backup" "Listing backups in ${dest}"
    found=0
    printf '%-6s %-16s %-8s %s\n' "TYPE" "DATE" "SIZE" "PATH"

    while IFS= read -r path; do
        [ -n "${path}" ] || continue
        name="$(basename "${path}")"

        case "${name}" in
            full-*.tar.gz)
                type="full"
                ;;
            incr-*)
                type="incr"
                ;;
            *)
                continue
                ;;
        esac

        date_value="$(detect_backup_date "${name}")"
        size="$(human_size "${path}")"
        printf '%-6s %-16s %-8s %s\n' "${type}" "${date_value}" "${size}" "${path}"
        found=1
    done <<EOF
$(find "${dest}" -maxdepth 1 \( -type f -name 'full-*.tar.gz' -o -type d -name 'incr-*' \) | sort)
EOF

    if [ "${found}" -eq 0 ]; then
        print_info "No backups found in ${dest}."
    fi

    end_time="$(timestamp)"
    log_backup_operation "list" "${start_time}" "${end_time}" "${dest}" "${dest}" "$(human_size "${dest}")" "success"
}

restore_backup() {
    local archive="${1:-}"
    local target="${2:-}"
    local assume_yes="false"
    local start_time end_time size

    if [ -z "${archive}" ] || [ -z "${target}" ]; then
        usage_error "restore requires <archive> and <target>."
        return 1
    fi

    start_time="$(timestamp)"

    if is_yes_flag "${3:-}"; then
        assume_yes="true"
    elif [ -n "${3:-}" ]; then
        print_error "Unknown restore option: ${3}"
        return 1
    fi

    if [ ! -f "${archive}" ]; then
        end_time="$(timestamp)"
        log_backup_operation "restore" "${start_time}" "${end_time}" "${archive}" "${target}" "0" "failure"
        print_error "Archive does not exist: ${archive}"
        return 1
    fi

    case "${archive}" in
        *.tar.gz)
            ;;
        *)
            end_time="$(timestamp)"
            log_backup_operation "restore" "${start_time}" "${end_time}" "${archive}" "${target}" "$(human_size "${archive}")" "failure"
            print_error "Restore only supports .tar.gz archives."
            return 1
            ;;
    esac

    if ! confirm_action "Restore ${archive} into ${target}?" "${assume_yes}"; then
        end_time="$(timestamp)"
        log_backup_operation "restore" "${start_time}" "${end_time}" "${archive}" "${target}" "$(human_size "${archive}")" "cancelled"
        print_warning "Restore cancelled."
        return 0
    fi

    mkdir -p "${target}"
    log_action "INFO" "backup" "Restore started: ${archive} -> ${target}"

    if tar -xzf "${archive}" -C "${target}"; then
        size="$(human_size "${target}")"
        end_time="$(timestamp)"
        log_backup_operation "restore" "${start_time}" "${end_time}" "${archive}" "${target}" "${size}" "success"
        log_action "INFO" "backup" "Restore completed: ${archive} -> ${target}"
        print_success "Archive restored into: ${target}"
    else
        end_time="$(timestamp)"
        log_backup_operation "restore" "${start_time}" "${end_time}" "${archive}" "${target}" "$(human_size "${archive}")" "failure"
        log_action "ERROR" "backup" "Restore failed: ${archive}"
        print_error "Restore failed."
        return 1
    fi
}

verify_backup() {
    local archive="${1:-}"
    local checksum_file archive_dir archive_file
    local tar_ok checksum_ok
    local start_time end_time outcome

    if [ -z "${archive}" ]; then
        usage_error "verify requires <archive>."
        return 1
    fi

    start_time="$(timestamp)"

    if [ ! -f "${archive}" ]; then
        end_time="$(timestamp)"
        log_backup_operation "verify" "${start_time}" "${end_time}" "${archive}" "${archive}" "0" "failure"
        print_error "Archive does not exist: ${archive}"
        return 1
    fi

    log_action "INFO" "backup" "Verification started: ${archive}"
    tar_ok=0
    checksum_ok=0

    if tar -tzf "${archive}" >/dev/null; then
        print_success "Tar archive integrity check passed."
        tar_ok=1
    else
        print_error "Tar archive integrity check failed."
    fi

    checksum_file="${archive}.sha256"
    if [ -f "${checksum_file}" ]; then
        archive_dir="$(cd "$(dirname "${archive}")" && pwd)"
        archive_file="$(basename "${archive}")"
        if (cd "${archive_dir}" && sha256sum -c "$(basename "${checksum_file}")" >/dev/null); then
            print_success "SHA-256 checksum verification passed for ${archive_file}."
            checksum_ok=1
        else
            print_error "SHA-256 checksum verification failed."
        fi
    else
        print_warning "Checksum file is missing: ${checksum_file}"
        checksum_ok=1
    fi

    if [ "${tar_ok}" -eq 1 ] && [ "${checksum_ok}" -eq 1 ]; then
        outcome="success"
        end_time="$(timestamp)"
        log_backup_operation "verify" "${start_time}" "${end_time}" "${archive}" "${archive}" "$(human_size "${archive}")" "${outcome}"
        log_action "INFO" "backup" "Verification passed: ${archive}"
        print_success "Backup verification passed: ${archive}"
    else
        outcome="failure"
        end_time="$(timestamp)"
        log_backup_operation "verify" "${start_time}" "${end_time}" "${archive}" "${archive}" "$(human_size "${archive}")" "${outcome}"
        log_action "ERROR" "backup" "Verification failed: ${archive}"
        return 1
    fi
}

rotate_backups() {
    local dest="${1:-}"
    local keep="${2:-}"
    local assume_yes="false"
    local backups_file total index path checksum
    local start_time end_time

    if [ -z "${dest}" ] || [ -z "${keep}" ]; then
        usage_error "rotate requires <dest> and <N>."
        return 1
    fi

    start_time="$(timestamp)"

    if is_yes_flag "${3:-}"; then
        assume_yes="true"
    elif [ -n "${3:-}" ]; then
        print_error "Unknown rotate option: ${3}"
        return 1
    fi

    if [ ! -d "${dest}" ]; then
        end_time="$(timestamp)"
        log_backup_operation "rotate" "${start_time}" "${end_time}" "${dest}" "${dest}" "0" "failure"
        print_error "Backup destination does not exist: ${dest}"
        return 1
    fi

    if ! is_positive_integer "${keep}"; then
        end_time="$(timestamp)"
        log_backup_operation "rotate" "${start_time}" "${end_time}" "${dest}" "${dest}" "$(human_size "${dest}")" "failure"
        print_error "N must be a positive integer."
        return 1
    fi

    backups_file="$(mktemp)"
    find "${dest}" -maxdepth 1 -type f -name 'full-*.tar.gz' | sort -r > "${backups_file}"
    total="$(wc -l < "${backups_file}" | tr -d ' ')"

    if [ "${total}" -le "${keep}" ]; then
        rm -f "${backups_file}"
        end_time="$(timestamp)"
        log_backup_operation "rotate" "${start_time}" "${end_time}" "${dest}" "${dest}" "$(human_size "${dest}")" "success"
        print_info "Found ${total} full backup(s); nothing to rotate."
        return 0
    fi

    print_info "Keeping ${keep} newest full backup(s) in ${dest}."
    print_warning "Older full backups and matching .sha256 files will be deleted."

    if ! confirm_action "Continue with backup rotation?" "${assume_yes}"; then
        rm -f "${backups_file}"
        end_time="$(timestamp)"
        log_backup_operation "rotate" "${start_time}" "${end_time}" "${dest}" "${dest}" "$(human_size "${dest}")" "cancelled"
        print_warning "Rotation cancelled."
        return 0
    fi

    log_action "INFO" "backup" "Rotation started in ${dest}, keeping ${keep} full backups."
    index=0
    while IFS= read -r path; do
        index=$((index + 1))
        if [ "${index}" -le "${keep}" ]; then
            print_info "Kept: ${path}"
            continue
        fi

        checksum="${path}.sha256"
        print_warning "Deleting: ${path}"
        rm -f "${path}"
        if [ -f "${checksum}" ]; then
            print_warning "Deleting: ${checksum}"
            rm -f "${checksum}"
        fi
    done < "${backups_file}"

    rm -f "${backups_file}"
    end_time="$(timestamp)"
    log_backup_operation "rotate" "${start_time}" "${end_time}" "${dest}" "${dest}" "$(human_size "${dest}")" "success"
    log_action "INFO" "backup" "Rotation completed in ${dest}."
    print_success "Backup rotation completed."
}

main() {
    local command_name="${1:-}"

    case "${command_name}" in
        -h|--help|"")
            show_help
            ;;
        full)
            shift
            create_full_backup "$@"
            ;;
        incr|incremental)
            shift
            create_incremental_backup "$@"
            ;;
        list)
            shift
            list_backups "$@"
            ;;
        restore)
            shift
            restore_backup "$@"
            ;;
        verify)
            shift
            verify_backup "$@"
            ;;
        rotate)
            shift
            rotate_backups "$@"
            ;;
        *)
            print_error "Unknown backup command: ${command_name}"
            show_help
            return 1
            ;;
    esac
}

main "$@"
