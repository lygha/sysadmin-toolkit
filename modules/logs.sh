#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"

show_help() {
    cat <<'EOF'
logs module

Usage:
  ./modules/logs.sh <command> [arguments]
  ./modules/logs.sh -h|--help

Commands:
  failed-logins [days]       Report failed SSH login attempts, default 7 days
  successful-logins [days]   Report successful SSH login attempts, default 7 days
  errors [days]              Report ERROR and CRITICAL syslog/messages lines
  top-ips                    Show top 10 failed-login source IPs
  summary                    Generate consolidated security report

Examples:
  sudo ./sysadmin.sh logs failed-logins 7
  sudo ./sysadmin.sh logs successful-logins 7
  sudo ./sysadmin.sh logs errors 7
  sudo ./sysadmin.sh logs top-ips
  sudo ./sysadmin.sh logs summary
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

validate_days() {
    local days="${1:-7}"

    case "${days}" in
        ''|*[!0-9]*)
            print_error "days must be a positive integer."
            return 1
            ;;
        *)
            if [ "${days}" -le 0 ]; then
                print_error "days must be a positive integer."
                return 1
            fi
            ;;
    esac
}

auth_log_file() {
    if [ -f /var/log/auth.log ]; then
        printf '%s\n' "/var/log/auth.log"
    elif [ -f /var/log/secure ]; then
        printf '%s\n' "/var/log/secure"
    else
        return 1
    fi
}

system_log_file() {
    if [ -f /var/log/syslog ]; then
        printf '%s\n' "/var/log/syslog"
    elif [ -f /var/log/messages ]; then
        printf '%s\n' "/var/log/messages"
    else
        return 1
    fi
}

report_header() {
    local title="$1"
    local days="$2"
    local source_file="$3"

    printf '%s\n' "${title}"
    printf 'Generated: %s\n' "$(timestamp)"
    printf 'Requested range: last %s day(s)\n' "${days}"
    printf 'Source log: %s\n' "${source_file}"
    printf 'Note: standard syslog text often omits the year, so this report parses the current plain log file and records the requested day range as context.\n\n'
}

print_missing_log_report() {
    local report_file="$1"
    local title="$2"
    local days="$3"
    local missing_kind="$4"

    {
        report_header "${title}" "${days}" "not found"
        printf 'WARNING: No %s log file was found.\n' "${missing_kind}"
        printf 'No results available.\n'
    } > "${report_file}"

    print_warning "No ${missing_kind} log file found. Empty report generated."
}

failed_login_rows() {
    local log_file="$1"

    awk '
        /Failed password/ {
            user="unknown"
            ip="unknown"

            for (i=1; i<=NF; i++) {
                if ($i == "for") {
                    if ($(i+1) == "invalid" && $(i+2) == "user") {
                        user=$(i+3)
                    } else {
                        user=$(i+1)
                    }
                }
                if ($i == "from") {
                    ip=$(i+1)
                }
            }

            if (ip != "unknown") {
                print ip "," user
            }
        }
    ' "${log_file}"
}

successful_login_rows() {
    local log_file="$1"

    awk '
        /Accepted / && / from / {
            user="unknown"
            ip="unknown"

            for (i=1; i<=NF; i++) {
                if ($i == "for") {
                    user=$(i+1)
                }
                if ($i == "from") {
                    ip=$(i+1)
                }
            }

            if (ip != "unknown") {
                print ip "," user
            }
        }
    ' "${log_file}"
}

write_login_report() {
    local mode="$1"
    local days="${2:-7}"
    local report_file="$3"
    local log_file="$4"
    local rows_file

    rows_file="$(mktemp)"

    if [ "${mode}" = "failed" ]; then
        failed_login_rows "${log_file}" > "${rows_file}"
    else
        successful_login_rows "${log_file}" > "${rows_file}"
    fi

    {
        if [ "${mode}" = "failed" ]; then
            report_header "Failed SSH Login Report" "${days}" "${log_file}"
        else
            report_header "Successful SSH Login Report" "${days}" "${log_file}"
        fi

        printf '=== Human-readable Summary ===\n'
        if [ ! -s "${rows_file}" ]; then
            printf 'No %s SSH login records found.\n' "${mode}"
        else
            printf '\nBy Source IP:\n'
            cut -d, -f1 "${rows_file}" | sort | uniq -c | sort -rn | awk '{ printf "%-18s %s\n", $2, $1 }'
            printf '\nBy Username:\n'
            cut -d, -f2 "${rows_file}" | sort | uniq -c | sort -rn | awk '{ printf "%-24s %s\n", $2, $1 }'
            printf '\nBy Source IP and Username:\n'
            sort "${rows_file}" | uniq -c | sort -rn | awk -F'[ ,]+' '{ printf "ip=%-18s user=%-24s count=%s\n", $2, $3, $1 }'
        fi

        printf '\n=== CSV: ip,username,count ===\n'
        printf 'ip,username,count\n'
        if [ -s "${rows_file}" ]; then
            sort "${rows_file}" | uniq -c | sort -rn | awk -F'[ ,]+' '{ printf "%s,%s,%s\n", $2, $3, $1 }'
        fi
    } > "${report_file}"

    rm -f "${rows_file}"
}

failed_logins() {
    local days="${1:-7}"
    local report_file log_file

    validate_days "${days}"
    require_root "logs"

    mkdir -p "$(reports_dir)"
    report_file="$(reports_dir)/failed-logins-$(report_timestamp).txt"

    log_action "INFO" "logs" "Failed login report started for ${days} day(s)."

    if log_file="$(auth_log_file)"; then
        write_login_report "failed" "${days}" "${report_file}" "${log_file}"
    else
        print_missing_log_report "${report_file}" "Failed SSH Login Report" "${days}" "authentication"
    fi

    print_success "Failed login report generated: ${report_file}"
    log_action "INFO" "logs" "Failed login report generated at ${report_file}."
}

successful_logins() {
    local days="${1:-7}"
    local report_file log_file

    validate_days "${days}"
    require_root "logs"

    mkdir -p "$(reports_dir)"
    report_file="$(reports_dir)/successful-logins-$(report_timestamp).txt"

    log_action "INFO" "logs" "Successful login report started for ${days} day(s)."

    if log_file="$(auth_log_file)"; then
        write_login_report "successful" "${days}" "${report_file}" "${log_file}"
    else
        print_missing_log_report "${report_file}" "Successful SSH Login Report" "${days}" "authentication"
    fi

    print_success "Successful login report generated: ${report_file}"
    log_action "INFO" "logs" "Successful login report generated at ${report_file}."
}

error_rows() {
    local log_file="$1"

    awk '
        BEGIN { IGNORECASE=1 }
        /ERROR|CRITICAL/ {
            program=$5
            sub(/\[[0-9]+\]:$/, "", program)
            sub(/:$/, "", program)
            if (program == "") {
                program="unknown"
            }
            print program "|" $0
        }
    ' "${log_file}"
}

errors_report() {
    local days="${1:-7}"
    local report_file log_file rows_file

    validate_days "${days}"
    require_root "logs"

    mkdir -p "$(reports_dir)"
    report_file="$(reports_dir)/errors-$(report_timestamp).txt"
    log_action "INFO" "logs" "Error report started for ${days} day(s)."

    if ! log_file="$(system_log_file)"; then
        print_missing_log_report "${report_file}" "System Error and Critical Message Report" "${days}" "system"
        print_success "Error report generated: ${report_file}"
        log_action "INFO" "logs" "Error report generated at ${report_file}."
        return 0
    fi

    rows_file="$(mktemp)"
    error_rows "${log_file}" > "${rows_file}"

    {
        report_header "System Error and Critical Message Report" "${days}" "${log_file}"

        printf '=== Human-readable Summary ===\n'
        if [ ! -s "${rows_file}" ]; then
            printf 'No ERROR or CRITICAL lines found.\n'
        else
            printf '\nFrequency by source program:\n'
            cut -d'|' -f1 "${rows_file}" | sort | uniq -c | sort -rn | awk '{ printf "%-30s %s\n", $2, $1 }'

            printf '\nMatching log lines:\n'
            cut -d'|' -f2- "${rows_file}"
        fi

        printf '\n=== CSV: program,count ===\n'
        printf 'program,count\n'
        if [ -s "${rows_file}" ]; then
            cut -d'|' -f1 "${rows_file}" | sort | uniq -c | sort -rn | awk '{ printf "%s,%s\n", $2, $1 }'
        fi
    } > "${report_file}"

    rm -f "${rows_file}"
    print_success "Error report generated: ${report_file}"
    log_action "INFO" "logs" "Error report generated at ${report_file}."
}

top_ips_report() {
    local report_file log_file rows_file

    require_root "logs"

    mkdir -p "$(reports_dir)"
    report_file="$(reports_dir)/top-ips-$(report_timestamp).txt"
    log_action "INFO" "logs" "Top failed-login IP report started."

    if ! log_file="$(auth_log_file)"; then
        print_missing_log_report "${report_file}" "Top Failed-login Source IP Report" "all available" "authentication"
        print_success "Top IP report generated: ${report_file}"
        log_action "INFO" "logs" "Top IP report generated at ${report_file}."
        return 0
    fi

    rows_file="$(mktemp)"
    failed_login_rows "${log_file}" > "${rows_file}"

    {
        report_header "Top Failed-login Source IP Report" "all available" "${log_file}"
        printf '=== Top 10 Source IPs ===\n'
        if [ ! -s "${rows_file}" ]; then
            printf 'No failed SSH login records found.\n'
        else
            cut -d, -f1 "${rows_file}" | sort | uniq -c | sort -rn | head -n 10 | awk '{ printf "%-18s %s\n", $2, $1 }'
        fi

        printf '\n=== CSV: ip,count ===\n'
        printf 'ip,count\n'
        if [ -s "${rows_file}" ]; then
            cut -d, -f1 "${rows_file}" | sort | uniq -c | sort -rn | head -n 10 | awk '{ printf "%s,%s\n", $2, $1 }'
        fi
    } > "${report_file}"

    rm -f "${rows_file}"
    print_success "Top IP report generated: ${report_file}"
    log_action "INFO" "logs" "Top IP report generated at ${report_file}."
}

summary_report() {
    local report_file auth_file sys_file failed_rows successful_rows error_data

    require_root "logs"

    mkdir -p "$(reports_dir)"
    report_file="$(reports_dir)/security-$(date '+%Y%m%d').txt"
    failed_rows="$(mktemp)"
    successful_rows="$(mktemp)"
    error_data="$(mktemp)"

    log_action "INFO" "logs" "Consolidated security summary started."

    if auth_file="$(auth_log_file)"; then
        failed_login_rows "${auth_file}" > "${failed_rows}"
        successful_login_rows "${auth_file}" > "${successful_rows}"
    else
        auth_file="not found"
        : > "${failed_rows}"
        : > "${successful_rows}"
    fi

    if sys_file="$(system_log_file)"; then
        error_rows "${sys_file}" > "${error_data}"
    else
        sys_file="not found"
        : > "${error_data}"
    fi

    {
        report_header "Consolidated Security Report" "all available" "auth=${auth_file}; system=${sys_file}"

        printf '=== Failed Login Summary ===\n'
        if [ ! -s "${failed_rows}" ]; then
            printf 'No failed SSH login records found.\n'
        else
            sort "${failed_rows}" | uniq -c | sort -rn | awk -F'[ ,]+' '{ printf "ip=%-18s user=%-24s count=%s\n", $2, $3, $1 }'
        fi

        printf '\n=== CSV: failed_ip,username,count ===\n'
        printf 'failed_ip,username,count\n'
        if [ -s "${failed_rows}" ]; then
            sort "${failed_rows}" | uniq -c | sort -rn | awk -F'[ ,]+' '{ printf "%s,%s,%s\n", $2, $3, $1 }'
        fi

        printf '\n=== Successful Login Summary ===\n'
        if [ ! -s "${successful_rows}" ]; then
            printf 'No successful SSH login records found.\n'
        else
            sort "${successful_rows}" | uniq -c | sort -rn | awk -F'[ ,]+' '{ printf "ip=%-18s user=%-24s count=%s\n", $2, $3, $1 }'
        fi

        printf '\n=== CSV: successful_ip,username,count ===\n'
        printf 'successful_ip,username,count\n'
        if [ -s "${successful_rows}" ]; then
            sort "${successful_rows}" | uniq -c | sort -rn | awk -F'[ ,]+' '{ printf "%s,%s,%s\n", $2, $3, $1 }'
        fi

        printf '\n=== Error/Critical Message Summary ===\n'
        if [ ! -s "${error_data}" ]; then
            printf 'No ERROR or CRITICAL lines found.\n'
        else
            cut -d'|' -f1 "${error_data}" | sort | uniq -c | sort -rn | awk '{ printf "%-30s %s\n", $2, $1 }'
        fi

        printf '\n=== CSV: error_program,count ===\n'
        printf 'error_program,count\n'
        if [ -s "${error_data}" ]; then
            cut -d'|' -f1 "${error_data}" | sort | uniq -c | sort -rn | awk '{ printf "%s,%s\n", $2, $1 }'
        fi

        printf '\n=== Top 10 Failed-login IPs ===\n'
        if [ ! -s "${failed_rows}" ]; then
            printf 'No failed SSH login IPs found.\n'
        else
            cut -d, -f1 "${failed_rows}" | sort | uniq -c | sort -rn | head -n 10 | awk '{ printf "%-18s %s\n", $2, $1 }'
        fi

        printf '\n=== CSV: top_failed_ip,count ===\n'
        printf 'top_failed_ip,count\n'
        if [ -s "${failed_rows}" ]; then
            cut -d, -f1 "${failed_rows}" | sort | uniq -c | sort -rn | head -n 10 | awk '{ printf "%s,%s\n", $2, $1 }'
        fi
    } > "${report_file}"

    rm -f "${failed_rows}" "${successful_rows}" "${error_data}"
    print_success "Security summary report generated: ${report_file}"
    log_action "INFO" "logs" "Security summary report generated at ${report_file}."
}

main() {
    local command_name="${1:-}"

    case "${command_name}" in
        -h|--help|"")
            show_help
            ;;
        failed-logins)
            shift
            failed_logins "${1:-7}"
            ;;
        successful-logins)
            shift
            successful_logins "${1:-7}"
            ;;
        errors)
            shift
            errors_report "${1:-7}"
            ;;
        top-ips)
            top_ips_report
            ;;
        summary)
            summary_report
            ;;
        *)
            print_error "Unknown logs command: ${command_name}"
            show_help
            return 1
            ;;
    esac
}

main "$@"
