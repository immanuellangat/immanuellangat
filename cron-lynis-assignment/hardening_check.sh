#!/bin/bash
#
# hardening_check.sh - run a Lynis audit, record the hardening index,
# and write a reminder when the score is below a threshold.

set -u
set -o pipefail

# ---- Settings ---------------------------------------------------------------
THRESHOLD=70

LYNIS=/usr/sbin/lynis
REPORT=/var/log/lynis-report.dat
RUN_LOG=/root/lynis-last-run.log
HISTORY=/var/log/hardening-history.csv
REMINDER=/var/log/hardening-reminder.log
LOCKFILE=/run/lock/hardening_check.lock

# Cron gives us almost no environment, so every command is an absolute path.
GREP=/usr/bin/grep
AWK=/usr/bin/awk
DATE=/usr/bin/date
FLOCK=/usr/bin/flock

# ---- Helpers ----------------------------------------------------------------
log_error() {
    echo "$($DATE '+%Y-%m-%d %H:%M:%S') ERROR: $*" >&2
}

# ---- Must be root -----------------------------------------------------------
if [ "$(/usr/bin/id -u)" -ne 0 ]; then
    log_error "this script must be run as root"
    exit 1
fi

# ---- Only one copy at a time (flock) ----------------------------------------
exec 9>"$LOCKFILE"
if ! $FLOCK -n 9; then
    log_error "another copy is already running, exiting"
    exit 1
fi

# ---- 1. Run Lynis non-interactively -----------------------------------------
# Remove the old report so a failed run cannot be mistaken for a fresh one.
/usr/bin/rm -f "$REPORT"

AUDIT_DATE=$($DATE '+%Y-%m-%d')
AUDIT_TIME=$($DATE '+%H:%M:%S')

if ! $LYNIS audit system --cronjob > "$RUN_LOG" 2>&1; then
    log_error "Lynis exited with an error, see $RUN_LOG"
    exit 1
fi

if [ ! -f "$REPORT" ]; then
    log_error "report file $REPORT does not exist"
    exit 1
fi

# ---- 2. Extract the score ---------------------------------------------------
SCORE=$($GREP '^hardening_index=' "$REPORT" | $AWK -F= '{print $2}')

if ! [[ "$SCORE" =~ ^[0-9]+$ ]]; then
    log_error "hardening_index is empty or not a number: '$SCORE'"
    exit 1
fi

# ---- 3. Record the result ---------------------------------------------------
# Write the header only when the file does not exist yet (or is empty).
if [ ! -s "$HISTORY" ]; then
    echo "date,time,score" > "$HISTORY"
fi
echo "$AUDIT_DATE,$AUDIT_TIME,$SCORE" >> "$HISTORY"

# ---- 4. Reminder ------------------------------------------------------------
if [ "$SCORE" -lt "$THRESHOLD" ]; then
    echo "$AUDIT_DATE $AUDIT_TIME REMINDER: hardening index is $SCORE, below the threshold of $THRESHOLD. Review $REPORT and apply the suggestions." >> "$REMINDER"
else
    echo "$AUDIT_DATE $AUDIT_TIME OK: hardening index is $SCORE (threshold $THRESHOLD). No action is needed." >> "$REMINDER"
fi

echo "$AUDIT_DATE $AUDIT_TIME hardening check finished, score=$SCORE threshold=$THRESHOLD"
exit 0
