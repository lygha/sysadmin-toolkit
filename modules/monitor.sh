#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"

show_help() {
    cat <<'EOF'
monitor module

Usage:
  ./modules/monitor.sh <command> [arguments]
  ./modules/monitor.sh -h|--help

Commands:
  cpu          Show CPU usage and top CPU-consuming processes
  mem          Show memory and swap usage plus top memory-consuming processes
  disk         Show disk usage per mounted partition
  proc         List running processes
  net          Show active network connections and listening ports
  watch [n]    Refresh monitoring dashboard every n seconds, default 5
  report       Generate a complete monitoring report in reports/

Examples:
  ./sysadmin.sh monitor cpu
  ./sysadmin.sh monitor mem
  ./sysadmin.sh monitor disk
  ./sysadmin.sh monitor watch 3
  ./modules/monitor.sh report
EOF
}

percent_to_int() {
    awk -v value="${1:-0}" 'BEGIN { printf "%d\n", value + 0 }'
}

read_cpu_values() {
    awk '/^cpu / {
        idle=$5
        total=0
        for (i=2; i<=NF; i++) {
            total += $i
        }
        printf "%s %s\n", idle, total
    }' /proc/stat
}

get_cpu_usage() {
    local first_idle first_total second_idle second_total idle_delta total_delta

    read -r first_idle first_total <<EOF
$(read_cpu_values)
EOF
    sleep 1
    read -r second_idle second_total <<EOF
$(read_cpu_values)
EOF

    idle_delta=$((second_idle - first_idle))
    total_delta=$((second_total - first_total))

    if [ "${total_delta}" -le 0 ]; then
        printf '0.00\n'
        return 0
    fi

    awk -v idle="${idle_delta}" -v total="${total_delta}" \
        'BEGIN { printf "%.2f\n", 100 * (total - idle) / total }'
}

show_top_cpu_processes() {
    printf '\nTop 5 CPU-consuming processes:\n'
    ps -eo pid,user,pcpu,pmem,comm --sort=-pcpu | head -n 6
}

show_cpu() {
    local usage usage_int

    log_action "INFO" "monitor" "CPU check started."
    usage="$(get_cpu_usage)"
    usage_int="$(percent_to_int "${usage}")"

    printf 'CPU Usage: %s%%\n' "${usage}"

    if [ "${usage_int}" -gt "${CPU_THRESHOLD}" ]; then
        print_warning "CPU usage ${usage}% is above threshold ${CPU_THRESHOLD}%."
        log_alert "CPU usage ${usage}% exceeded threshold ${CPU_THRESHOLD}%."
    fi

    show_top_cpu_processes
    log_action "INFO" "monitor" "CPU check completed."
}

show_mem() {
    local mem_line swap_line total used mem_percent mem_percent_int

    log_action "INFO" "monitor" "Memory check started."

    printf 'Memory and swap usage:\n'
    free -h

    mem_line="$(free -m | awk '/^Mem:/ { print $2, $3 }')"
    swap_line="$(free -m | awk '/^Swap:/ { print $2, $3, $4 }')"
    read -r total used <<EOF
${mem_line}
EOF

    if [ "${total}" -gt 0 ]; then
        mem_percent="$(awk -v used="${used}" -v total="${total}" 'BEGIN { printf "%.2f\n", used * 100 / total }')"
    else
        mem_percent="0.00"
    fi

    mem_percent_int="$(percent_to_int "${mem_percent}")"
    printf '\nMemory Usage: %s%%\n' "${mem_percent}"

    if [ -n "${swap_line}" ]; then
        printf 'Swap MB total/used/free: %s\n' "${swap_line}"
    fi

    if [ "${mem_percent_int}" -gt "${MEM_THRESHOLD}" ]; then
        print_warning "Memory usage ${mem_percent}% is above threshold ${MEM_THRESHOLD}%."
        log_alert "Memory usage ${mem_percent}% exceeded threshold ${MEM_THRESHOLD}%."
    fi

    printf '\nTop 5 memory-consuming processes:\n'
    ps -eo pid,user,pcpu,pmem,comm --sort=-pmem | head -n 6
    log_action "INFO" "monitor" "Memory check completed."
}

show_disk() {
    local alert_count

    log_action "INFO" "monitor" "Disk check started."
    printf 'Disk usage by mounted partition:\n'
    df -h -x tmpfs -x devtmpfs

    alert_count=0
    while read -r filesystem size used avail percent mountpoint; do
        local usage
        usage="${percent%\%}"

        if [ "${usage}" -gt "${DISK_THRESHOLD}" ]; then
            print_warning "Disk usage on ${mountpoint} is ${percent}, above threshold ${DISK_THRESHOLD}%."
            log_alert "Disk usage on ${mountpoint} (${filesystem}) is ${percent}, exceeded threshold ${DISK_THRESHOLD}%."
            alert_count=$((alert_count + 1))
        fi
    done <<EOF
$(df -P -x tmpfs -x devtmpfs | awk 'NR > 1 { print $1, $2, $3, $4, $5, $6 }')
EOF

    if [ "${alert_count}" -eq 0 ]; then
        print_success "No mounted partitions are above ${DISK_THRESHOLD}%."
    fi

    log_action "INFO" "monitor" "Disk check completed."
}

show_proc() {
    log_action "INFO" "monitor" "Process listing started."
    printf 'Running processes:\n'
    ps -eo pid,user,pcpu,pmem,args --sort=-pcpu | head -n 31
    log_action "INFO" "monitor" "Process listing completed."
}

show_net() {
    log_action "INFO" "monitor" "Network check started."

    if command_exists ss; then
        printf 'Active network connections and listening ports using ss:\n'
        ss -tulpen
    elif command_exists netstat; then
        printf 'Active network connections and listening ports using netstat:\n'
        netstat -tulpen
    else
        print_error "Neither ss nor netstat is installed. Cannot show network connections."
        log_action "ERROR" "monitor" "Network check failed: ss and netstat not found."
        return 1
    fi

    log_action "INFO" "monitor" "Network check completed."
}

show_dashboard() {
    local cpu_usage mem_percent disk_summary

    cpu_usage="$(get_cpu_usage)"
    mem_percent="$(free -m | awk '/^Mem:/ { if ($2 > 0) printf "%.2f", $3 * 100 / $2; else printf "0.00" }')"
    disk_summary="$(df -h -x tmpfs -x devtmpfs | awk 'NR == 1 || NR <= 6')"

    clear
    printf 'sysadmin-toolkit monitoring dashboard\n'
    printf 'Updated: %s\n\n' "$(timestamp)"

    printf 'CPU Usage: %s%%  Threshold: %s%%\n' "${cpu_usage}" "${CPU_THRESHOLD}"
    printf 'Memory Usage: %s%%  Threshold: %s%%\n\n' "${mem_percent}" "${MEM_THRESHOLD}"

    printf 'Disk Usage:\n%s\n\n' "${disk_summary}"

    printf 'Top CPU processes:\n'
    ps -eo pid,user,pcpu,pmem,comm --sort=-pcpu | head -n 6
}

watch_dashboard() {
    local interval="${1:-5}"

    if ! awk -v n="${interval}" 'BEGIN { exit !(n ~ /^[0-9]+$/ && n > 0) }'; then
        print_error "watch interval must be a positive number of seconds."
        return 1
    fi

    log_action "INFO" "monitor" "Watch dashboard started with interval ${interval}s."

    trap 'printf "\n"; print_info "Monitoring watch stopped."; log_action "INFO" "monitor" "Watch dashboard stopped."; exit 0' INT TERM

    while true; do
        show_dashboard
        sleep "${interval}"
    done
}

generate_report() {
    local report_dir report_file

    log_action "INFO" "monitor" "Monitoring report generation started."
    report_dir="${PROJECT_ROOT}/${REPORTS_DIR}"
    mkdir -p "${report_dir}"
    report_file="${report_dir}/monitor-$(date '+%Y%m%d-%H%M%S').txt"

    {
        printf 'sysadmin-toolkit Monitoring Report\n'
        printf 'Generated: %s\n\n' "$(timestamp)"

        printf '=== CPU ===\n'
        show_cpu
        printf '\n\n=== Memory ===\n'
        show_mem
        printf '\n\n=== Disk ===\n'
        show_disk
        printf '\n\n=== Processes ===\n'
        show_proc
        printf '\n\n=== Network ===\n'
        show_net || true
    } > "${report_file}"

    print_success "Monitoring report generated: ${report_file}"
    log_action "INFO" "monitor" "Monitoring report generated at ${report_file}."
}

main() {
    local command_name="${1:-}"

    case "${command_name}" in
        -h|--help|"")
            show_help
            ;;
        cpu)
            show_cpu
            ;;
        mem|memory)
            show_mem
            ;;
        disk)
            show_disk
            ;;
        proc|processes)
            show_proc
            ;;
        net|network)
            show_net
            ;;
        watch)
            shift
            watch_dashboard "${1:-5}"
            ;;
        report)
            generate_report
            ;;
        *)
            print_error "Unknown monitor command: ${command_name}"
            show_help
            return 1
            ;;
    esac
}

main "$@"
