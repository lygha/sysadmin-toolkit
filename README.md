# Linux SysAdmin Toolkit

## Project Overview

Linux SysAdmin Toolkit is a Bash-based Linux system administration toolkit for
an Operating Systems project. It provides one main dispatcher script,
`sysadmin.sh`, with separate modules for monitoring, backups, user management,
log analysis, reporting, and logging.

The project was tested successfully on Ubuntu Server running inside VMware.

## Features

- Monitoring
- Backups
- User management
- Log analysis
- Reporting
- Logging

## Project Structure

```text
sysadmin-toolkit/
|-- sysadmin.sh
|-- demo.sh
|-- README.md
|-- config/
|   `-- toolkit.conf
|-- lib/
|   `-- common.sh
|-- modules/
|   |-- monitor.sh
|   |-- backup.sh
|   |-- users.sh
|   `-- logs.sh
|-- samples/
|   |-- users.csv
|   `-- test-data/
|-- reports/
|-- logs/
|-- backups/
`-- screenshots/
    `-- README.txt
```

## Installation

Clone the project and enter the toolkit folder:

```bash
git clone https://github.com/lygha/sysadmin-toolkit.git
cd sysadmin-toolkit
```

Make the scripts executable:

```bash
chmod +x sysadmin.sh demo.sh lib/common.sh modules/*.sh
```

## Usage

Run commands through the main dispatcher:

```bash
./sysadmin.sh <module> <command> [arguments]
```

General help:

```bash
./sysadmin.sh --help
```

## Module Descriptions

### monitor

Provides system monitoring commands for CPU, memory, disk usage, processes,
network information, and monitoring reports.

### backup

Creates full and incremental backups, lists backup archives, verifies backup
files, restores archives into a target folder, and rotates old backups.

### users

Lists human users, creates demo users from a CSV file, deletes demo users,
generates user audit reports, and scans directories for world-writable files.

### logs

Analyzes Linux system logs for failed logins, successful logins, error messages,
top IP addresses, and summary reports.

## Example Commands

Monitoring:

```bash
./sysadmin.sh monitor cpu
./sysadmin.sh monitor mem
./sysadmin.sh monitor disk
./sysadmin.sh monitor proc
./sysadmin.sh monitor net
./sysadmin.sh monitor report
```

Backups:

```bash
./sysadmin.sh backup full ./samples/test-data ./backups
./sysadmin.sh backup incr ./samples/test-data ./backups
./sysadmin.sh backup list ./backups
./sysadmin.sh backup verify ./backups/full-test-data-YYYYMMDD-HHMMSS.tar.gz
./sysadmin.sh backup restore ./backups/full-test-data-YYYYMMDD-HHMMSS.tar.gz ./restore-test
./sysadmin.sh backup rotate ./backups 3
```

User management:

```bash
./sysadmin.sh users list
./sysadmin.sh users perms ./samples
sudo ./sysadmin.sh users add-bulk ./samples/users.csv
sudo ./sysadmin.sh users delete testuser1 --archive-home
sudo ./sysadmin.sh users delete testuser2 -y
sudo ./sysadmin.sh users audit
```

Log analysis:

```bash
sudo ./sysadmin.sh logs failed-logins 7
sudo ./sysadmin.sh logs successful-logins 7
sudo ./sysadmin.sh logs errors 7
sudo ./sysadmin.sh logs top-ips
sudo ./sysadmin.sh logs summary
```

## Root Required Commands

These commands require `sudo` because they create/delete Linux users, inspect
protected account information, or read protected system logs:

```bash
sudo ./sysadmin.sh users add-bulk ./samples/users.csv
sudo ./sysadmin.sh users delete testuser1 --archive-home
sudo ./sysadmin.sh users delete testuser2 -y
sudo ./sysadmin.sh users audit

sudo ./sysadmin.sh logs failed-logins 7
sudo ./sysadmin.sh logs successful-logins 7
sudo ./sysadmin.sh logs errors 7
sudo ./sysadmin.sh logs top-ips
sudo ./sysadmin.sh logs summary
```

Use user creation and deletion commands only with demo/test users unless you
intentionally want to modify real Linux accounts.

## Demo Instructions

Run the safe demonstration from the project root:

```bash
./demo.sh
```

The demo runs safe monitoring, backup, restore-to-`restore-demo`, user listing,
permission scanning, report display, and log display commands. `demo.sh`
intentionally avoids destructive/root-only operations such as Linux user
creation, user deletion, and protected system log analysis.

## Reports and Logs

Reports are written to:

```text
reports/
```

Toolkit logs are written to:

```text
logs/
```

Useful files include `logs/toolkit.log`, `logs/backup.log`, and generated report
files such as permission or monitoring reports.

## Testing

Run the Bash syntax check:

```bash
bash -n sysadmin.sh demo.sh lib/common.sh modules/*.sh
```

Run the safe end-to-end demo:

```bash
./demo.sh
```

Recommended quick manual checks:

```bash
./sysadmin.sh --help
./sysadmin.sh monitor cpu
./sysadmin.sh monitor disk
./sysadmin.sh users list
./sysadmin.sh users perms ./samples
```

## Known Limitations

- Rotated compressed logs are not parsed.
- Exact syslog day filtering is conservative.
- Incremental backups depend on `rsync`.
- Email alerts are optional and disabled.

## Future Improvements

- Email alerts
- JSON export
- Dashboard improvements
- Cron automation helper

## Author

Ahmad Ghalayini
