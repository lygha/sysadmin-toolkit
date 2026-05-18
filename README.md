# sysadmin-toolkit

A Bash-based Linux System Administration Toolkit for a university Operating
Systems lab project.

The toolkit has one main dispatcher, `sysadmin.sh`, and separate modules for
monitoring, user administration, backup automation, and log inspection.

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
|   |-- users.sh
|   |-- backup.sh
|   `-- logs.sh
|-- reports/
|-- logs/
|-- samples/
|   |-- users.csv
|   `-- test-data/
`-- backups/
```

## Basic Usage

From the project root:

```bash
chmod +x sysadmin.sh demo.sh lib/common.sh modules/*.sh
./sysadmin.sh --help
```

Modules can also be run directly:

```bash
./modules/monitor.sh --help
./modules/backup.sh --help
```

## Quick Demo

Run the safe two-minute demo from the project root:

```bash
chmod +x sysadmin.sh demo.sh modules/*.sh
./demo.sh
```

The demo runs safe monitoring, backup, restore-to-`restore-demo`, user listing,
and permission scanning commands. It intentionally avoids destructive or
root-required commands such as creating/deleting Linux users and reading
protected system logs.

## Monitoring Examples

```bash
./sysadmin.sh monitor cpu
./sysadmin.sh monitor mem
./sysadmin.sh monitor disk
./sysadmin.sh monitor proc
./sysadmin.sh monitor net
./sysadmin.sh monitor report
```

## Backup Examples

Safe sample data is included in `samples/test-data/`, so you can test backup
commands without touching real system folders.

Create a full compressed backup:

```bash
./sysadmin.sh backup full ./samples/test-data ./backups
```

Create an incremental backup:

```bash
./sysadmin.sh backup incr ./samples/test-data ./backups
```

List backups:

```bash
./sysadmin.sh backup list ./backups
```

Verify a full backup:

```bash
./sysadmin.sh backup verify ./backups/full-test-data-YYYYMMDD-HHMMSS.tar.gz
```

Restore a full backup into a test folder:

```bash
./sysadmin.sh backup restore ./backups/full-test-data-YYYYMMDD-HHMMSS.tar.gz ./restore-test
```

Rotate full backups and keep only the 3 newest:

```bash
./sysadmin.sh backup rotate ./backups 3
```

Use `-y` or `--yes` to skip confirmation for restore and rotate:

```bash
./sysadmin.sh backup restore ./backups/full-test-data-YYYYMMDD-HHMMSS.tar.gz ./restore-test -y
./sysadmin.sh backup rotate ./backups 3 --yes
```

## User Management Examples

The user module can list users without sudo:

```bash
./sysadmin.sh users list
```

Create demo/test users from the safe sample CSV:

```bash
sudo ./sysadmin.sh users add-bulk ./samples/users.csv
```

The sample CSV contains only demo users:

```text
username,fullname,group
testuser1,Test User One,students
testuser2,Test User Two,students
```

Delete demo/test users only. This removes the user's home directory, so use it
carefully:

```bash
sudo ./sysadmin.sh users delete testuser1 --archive-home
sudo ./sysadmin.sh users delete testuser2 -y
```

Generate a root-only user security audit:

```bash
sudo ./sysadmin.sh users audit
```

Scan a directory for world-writable files and directories:

```bash
./sysadmin.sh users perms ./samples
```

## Log Analysis Examples

System log analysis reads protected files such as `/var/log/auth.log`,
`/var/log/secure`, `/var/log/syslog`, and `/var/log/messages`, so these commands
require sudo:

```bash
sudo ./sysadmin.sh logs failed-logins 7
sudo ./sysadmin.sh logs successful-logins 7
sudo ./sysadmin.sh logs errors 7
sudo ./sysadmin.sh logs top-ips
sudo ./sysadmin.sh logs summary
```

Reports are written to `reports/` as plain-text files and include both readable
sections and CSV sections.

## Root-required Commands

These commands require sudo because they modify Linux users or read protected
system files:

```bash
sudo ./sysadmin.sh users add-bulk ./samples/users.csv
sudo ./sysadmin.sh users delete testuser1 --archive-home
sudo ./sysadmin.sh users audit

sudo ./sysadmin.sh logs failed-logins 7
sudo ./sysadmin.sh logs successful-logins 7
sudo ./sysadmin.sh logs errors 7
sudo ./sysadmin.sh logs top-ips
sudo ./sysadmin.sh logs summary
```

Use the user commands only with demo/test users unless you intentionally want to
modify real Linux accounts.

## Sample Crontab Entries

Daily incremental backup at 2:00 AM:

```cron
0 2 * * * /path/to/sysadmin-toolkit/sysadmin.sh backup incr /path/to/source /path/to/backups
```

Weekly full backup on Sunday at 3:00 AM:

```cron
0 3 * * 0 /path/to/sysadmin-toolkit/sysadmin.sh backup full /path/to/source /path/to/backups
```

## Notes

- Backup commands do not require sudo for normal user-owned files.
- Destructive backup commands ask for confirmation unless `-y` or `--yes` is used.
- User creation, deletion, and audit commands require sudo.
- Log analysis commands require sudo because system logs are protected.

## Final Verification Checklist

```bash
bash -n sysadmin.sh demo.sh lib/common.sh modules/*.sh
./sysadmin.sh --help
./demo.sh
```
