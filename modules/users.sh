#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"

show_help() {
    cat <<'EOF'
users module

Usage:
  ./modules/users.sh <command> [arguments]
  ./modules/users.sh -h|--help

Commands:
  add-bulk <file.csv>                    Create users from CSV, requires root
  delete <username> [-y|--yes] [--archive-home]
                                         Delete a user, requires root
  list                                   List human users
  audit                                  Generate user security audit, requires root
  perms <directory>                      Report world-writable files/directories

CSV format for add-bulk:
  username,fullname,group

Examples:
  ./sysadmin.sh users list
  sudo ./sysadmin.sh users add-bulk ./samples/users.csv
  sudo ./sysadmin.sh users delete testuser1 --archive-home
  sudo ./sysadmin.sh users audit
  ./sysadmin.sh users perms ./samples
EOF
}

usage_error() {
    print_error "$1"
    show_help
    return 1
}

report_timestamp() {
    date '+%Y%m%d-%H%M%S'
}

reports_dir() {
    printf '%s/%s\n' "${PROJECT_ROOT}" "${REPORTS_DIR:-reports}"
}

trim_field() {
    printf '%s' "$1" | awk '{$1=$1; print}'
}

valid_username() {
    case "${1:-}" in
        ''|*[!a-zA-Z0-9._-]*)
            return 1
            ;;
        -*|.*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

user_exists() {
    getent passwd "$1" >/dev/null 2>&1
}

group_exists() {
    getent group "$1" >/dev/null 2>&1
}

generate_password() {
    if command_exists openssl; then
        openssl rand -base64 18 | tr -d '\n'
    elif command_exists sha256sum; then
        printf '%s-%s-%s\n' "$$" "$(date '+%s')" "${RANDOM:-0}" | sha256sum | awk '{ print substr($1, 1, 18) }'
    else
        printf 'ChangeMe-%s\n' "$(date '+%s')"
    fi
}

create_group_if_missing() {
    local group_name="$1"

    if group_exists "${group_name}"; then
        return 0
    fi

    groupadd "${group_name}"
    print_info "Created group: ${group_name}"
    log_action "INFO" "users" "Created group ${group_name}."
}

add_bulk_users() {
    local csv_file="${1:-}"
    local credentials_file line username fullname group_name password
    local line_number created_count skipped_count

    if [ -z "${csv_file}" ]; then
        usage_error "add-bulk requires <file.csv>."
        return 1
    fi

    require_root "users"

    if [ ! -f "${csv_file}" ]; then
        print_error "CSV file does not exist: ${csv_file}"
        return 1
    fi

    if ! command_exists useradd || ! command_exists groupadd || ! command_exists chpasswd; then
        print_error "Required commands missing. Need useradd, groupadd, and chpasswd."
        return 1
    fi

    mkdir -p "$(reports_dir)"
    credentials_file="$(reports_dir)/user-credentials-$(report_timestamp).txt"

    {
        printf 'sysadmin-toolkit User Credentials Report\n'
        printf 'Generated: %s\n' "$(timestamp)"
        printf 'Source CSV: %s\n\n' "${csv_file}"
        printf '%-20s %-24s %s\n' "USERNAME" "GROUP" "INITIAL_PASSWORD"
    } > "${credentials_file}"
    chmod 600 "${credentials_file}"

    created_count=0
    skipped_count=0
    line_number=0

    log_action "INFO" "users" "Bulk user creation started from ${csv_file}."

    while IFS=, read -r username fullname group_name extra || [ -n "${username:-}" ]; do
        line_number=$((line_number + 1))

        username="$(trim_field "${username:-}")"
        fullname="$(trim_field "${fullname:-}")"
        group_name="$(trim_field "${group_name:-}")"

        if [ "${line_number}" -eq 1 ] && [ "${username}" = "username" ]; then
            continue
        fi

        if [ -n "${extra:-}" ]; then
            print_warning "Line ${line_number}: extra CSV fields ignored."
        fi

        if [ -z "${username}" ]; then
            print_warning "Line ${line_number}: empty username skipped."
            log_action "WARNING" "users" "Skipped line ${line_number}: empty username."
            skipped_count=$((skipped_count + 1))
            continue
        fi

        if ! valid_username "${username}"; then
            print_warning "Line ${line_number}: invalid username skipped: ${username}"
            log_action "WARNING" "users" "Skipped invalid username ${username}."
            skipped_count=$((skipped_count + 1))
            continue
        fi

        if [ -z "${group_name}" ]; then
            print_warning "Line ${line_number}: group is empty for ${username}, skipped."
            log_action "WARNING" "users" "Skipped ${username}: empty group."
            skipped_count=$((skipped_count + 1))
            continue
        fi

        if user_exists "${username}"; then
            print_warning "User already exists, skipped: ${username}"
            log_action "WARNING" "users" "Skipped existing user ${username}."
            skipped_count=$((skipped_count + 1))
            continue
        fi

        create_group_if_missing "${group_name}"
        password="$(generate_password)"

        if useradd -m -s /bin/bash -c "${fullname}" -g "${group_name}" "${username}" &&
            printf '%s:%s\n' "${username}" "${password}" | chpasswd; then
            printf '%-20s %-24s %s\n' "${username}" "${group_name}" "${password}" >> "${credentials_file}"
            print_success "Created user: ${username}"
            log_action "INFO" "users" "Created user ${username} in group ${group_name}."
            created_count=$((created_count + 1))
        else
            print_error "Failed to create user: ${username}"
            log_action "ERROR" "users" "Failed to create user ${username}."
            skipped_count=$((skipped_count + 1))
        fi
    done < "${csv_file}"

    chmod 600 "${credentials_file}"
    print_success "Bulk user creation complete. Created=${created_count}, skipped=${skipped_count}."
    print_info "Credentials saved to: ${credentials_file}"
    log_action "INFO" "users" "Bulk user creation completed. Created=${created_count}, skipped=${skipped_count}."
}

delete_user() {
    local username="${1:-}"
    local assume_yes="false"
    local archive_home="false"
    local home_dir option archive_path

    if [ -z "${username}" ]; then
        usage_error "delete requires <username>."
        return 1
    fi

    require_root "users"

    shift || true
    for option in "$@"; do
        case "${option}" in
            -y|--yes)
                assume_yes="true"
                ;;
            --archive-home)
                archive_home="true"
                ;;
            *)
                print_error "Unknown delete option: ${option}"
                return 1
                ;;
        esac
    done

    if ! valid_username "${username}"; then
        print_error "Invalid username: ${username}"
        return 1
    fi

    if ! user_exists "${username}"; then
        print_error "User does not exist: ${username}"
        return 1
    fi

    home_dir="$(getent passwd "${username}" | cut -d: -f6)"

    if ! confirm_action "Delete user ${username} and remove home directory ${home_dir}?" "${assume_yes}"; then
        print_warning "User deletion cancelled."
        log_action "WARNING" "users" "Deletion cancelled for user ${username}."
        return 0
    fi

    log_action "INFO" "users" "User deletion started for ${username}."

    if [ "${archive_home}" = "true" ] && [ -d "${home_dir}" ]; then
        mkdir -p /var/backups
        archive_path="/var/backups/${username}-home-$(report_timestamp).tar.gz"
        if tar -czf "${archive_path}" -C "$(dirname "${home_dir}")" "$(basename "${home_dir}")"; then
            print_success "Archived home directory to: ${archive_path}"
            log_action "INFO" "users" "Archived home for ${username} to ${archive_path}."
        else
            print_error "Failed to archive home directory for ${username}."
            log_action "ERROR" "users" "Failed to archive home for ${username}."
            return 1
        fi
    fi

    if userdel -r "${username}"; then
        print_success "Deleted user and home directory: ${username}"
        log_action "INFO" "users" "Deleted user ${username}."
    else
        print_error "Failed to delete user: ${username}"
        log_action "ERROR" "users" "Failed to delete user ${username}."
        return 1
    fi
}

last_login_for_user() {
    local username="$1"
    local result

    if ! command_exists last; then
        printf 'last unavailable\n'
        return 0
    fi

    result="$(last -n 1 "${username}" 2>/dev/null | awk 'NR == 1 {
        if ($0 ~ /wtmp begins/) {
            print "never"
        } else {
            $1=""
            sub(/^ +/, "")
            print
        }
    }')"

    if [ -z "${result}" ]; then
        printf 'never\n'
    else
        printf '%s\n' "${result}"
    fi
}

list_users() {
    local username uid gid home shell last_login

    log_action "INFO" "users" "Human user list requested."
    printf '%-20s %-8s %-8s %-28s %-18s %s\n' "USERNAME" "UID" "GID" "HOME" "SHELL" "LAST_LOGIN"

    while IFS=: read -r username _ uid gid _ home shell; do
        if [ "${uid}" -ge 1000 ] && [ "${username}" != "nobody" ]; then
            last_login="$(last_login_for_user "${username}")"
            printf '%-20s %-8s %-8s %-28s %-18s %s\n' "${username}" "${uid}" "${gid}" "${home}" "${shell}" "${last_login}"
        fi
    done < /etc/passwd
}

audit_users() {
    local report_file today_days username uid last_change age_days path

    require_root "users"

    mkdir -p "$(reports_dir)"
    report_file="$(reports_dir)/users-audit-$(report_timestamp).txt"
    today_days="$(( $(date '+%s') / 86400 ))"

    log_action "INFO" "users" "User audit started."

    {
        printf 'sysadmin-toolkit User Security Audit\n'
        printf 'Generated: %s\n\n' "$(timestamp)"

        printf '=== Users With UID 0 ===\n'
        awk -F: '$3 == 0 { printf "%s uid=%s gid=%s home=%s shell=%s\n", $1, $3, $4, $6, $7 }' /etc/passwd

        printf '\n=== Users With Empty Passwords ===\n'
        awk -F: '$2 == "" { print $1 }' /etc/shadow

        printf '\n=== Passwords Not Changed In Last 90 Days ===\n'
        if ! command_exists chage; then
            printf 'WARNING: chage command unavailable; using /etc/shadow age data.\n'
        else
            printf 'Using /etc/shadow age data; chage is available for manual follow-up.\n'
        fi

        while IFS=: read -r username _ last_change _ _ _ _ _ _; do
            if [ "${last_change}" = "" ] || [ "${last_change}" = "0" ]; then
                printf '%s: password age unknown or never changed\n' "${username}"
                continue
            fi

            case "${last_change}" in
                *[!0-9]*)
                    continue
                    ;;
            esac

            age_days=$((today_days - last_change))
            if [ "${age_days}" -gt 90 ]; then
                printf '%s: last changed %s days ago\n' "${username}" "${age_days}"
            fi
        done < /etc/shadow

        printf '\n=== SUID and SGID Files Under /usr, /bin, /sbin ===\n'
        for path in /usr /bin /sbin; do
            if [ -d "${path}" ]; then
                find "${path}" -xdev \( -perm -4000 -o -perm -2000 \) -type f -print 2>/dev/null
            else
                printf 'WARNING: path not found: %s\n' "${path}"
            fi
        done
    } > "${report_file}"

    print_success "User audit report generated: ${report_file}"
    log_action "INFO" "users" "User audit report generated at ${report_file}."
}

permissions_report() {
    local directory="${1:-}"
    local report_file found

    if [ -z "${directory}" ]; then
        usage_error "perms requires <directory>."
        return 1
    fi

    if [ ! -d "${directory}" ]; then
        print_error "Directory does not exist: ${directory}"
        return 1
    fi

    mkdir -p "$(reports_dir)"
    report_file="$(reports_dir)/permissions-$(report_timestamp).txt"
    log_action "INFO" "users" "Permission scan started for ${directory}."

    {
        printf 'sysadmin-toolkit Permissions Report\n'
        printf 'Generated: %s\n' "$(timestamp)"
        printf 'Directory: %s\n\n' "${directory}"
        printf '=== World-writable Files and Directories ===\n'
    } > "${report_file}"

    found=0
    while IFS= read -r path; do
        [ -n "${path}" ] || continue
        found=1
        printf 'RISK: %s\n' "${path}" | tee -a "${report_file}"
    done <<EOF
$(find "${directory}" -perm -0002 -print 2>/dev/null | sort)
EOF

    if [ "${found}" -eq 0 ]; then
        printf 'No world-writable files found.\n' | tee -a "${report_file}"
    fi

    print_success "Permissions report generated: ${report_file}"
    log_action "INFO" "users" "Permission report generated at ${report_file}."
}

main() {
    local command_name="${1:-}"

    case "${command_name}" in
        -h|--help|"")
            show_help
            ;;
        add-bulk)
            shift
            add_bulk_users "$@"
            ;;
        delete)
            shift
            delete_user "$@"
            ;;
        list)
            list_users
            ;;
        audit)
            audit_users
            ;;
        perms)
            shift
            permissions_report "$@"
            ;;
        *)
            print_error "Unknown users command: ${command_name}"
            show_help
            return 1
            ;;
    esac
}

main "$@"
