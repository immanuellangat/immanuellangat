# Group 2: Cron and Lynis — Practice and Research Assignment

Environment: Ubuntu 24.04.5 LTS, Lynis 3.0.9. All output below is real output
from running the commands on the test machine on 2026-11-15.

> **Screenshots:** every block marked 📸 is a point where a screenshot belongs.
> Re-run the command on your own VM and paste the screenshot there. Your scores
> will differ from mine because the machines differ.

---

## 1. Set up

```bash
sudo apt update && sudo apt install lynis
lynis show version
```

```
3.0.9
```

Manual audit, then find the hardening index in the screen output and in the
report file:

```bash
sudo lynis audit system
sudo grep hardening_index /var/log/lynis-report.dat
```

📸
```
  Hardening index : 57 [###########         ]
  Tests performed : 241
  Plugins enabled : 1
...
hardening_index=57
```

**Starting score: 57.**

### Crontab fields

| # | Field | Allowed values |
|---|-------|----------------|
| 1 | minute | 0–59 |
| 2 | hour | 0–23 |
| 3 | day of month | 1–31 |
| 4 | month | 1–12 (or jan–dec) |
| 5 | day of week | 0–7 (0 and 7 are Sunday, or sun–sat) |

Files in `/etc/cron.d/` (and `/etc/crontab`) have a **sixth field, the user**,
between the time fields and the command. These are system files, not owned by
one user's crontab, so cron has to be told which account runs the job. A
personal crontab (`crontab -e`) has no user field.

---

## 2. The script

Full script: [`hardening_check.sh`](hardening_check.sh) (also in the appendix).

Install it owned by root and writable by nobody else:

```bash
sudo install -o root -g root -m 700 hardening_check.sh /usr/local/sbin/hardening_check.sh
ls -l /usr/local/sbin/hardening_check.sh
```

📸
```
-rwx------ 1 root root 3097 Nov 15 06:17 /usr/local/sbin/hardening_check.sh
```

How it meets each instruction:

| Instruction | In the script |
|-------------|---------------|
| `#!/bin/bash`, `set -u`, `set -o pipefail` | first lines |
| Absolute paths for every command and file | `LYNIS=/usr/sbin/lynis`, `GREP=/usr/bin/grep`, `AWK=/usr/bin/awk`, `DATE=/usr/bin/date`, … |
| Run Lynis non-interactively, save output | `$LYNIS audit system --cronjob > /root/lynis-last-run.log 2>&1` |
| Exit if Lynis fails or the report is missing | `if ! $LYNIS …; then … exit 1` and `if [ ! -f "$REPORT" ]` |
| Extract the score with grep and awk | `$GREP '^hardening_index=' "$REPORT" \| $AWK -F= '{print $2}'` |
| Check the value is a number | `[[ "$SCORE" =~ ^[0-9]+$ ]]`, otherwise log an error and exit |
| CSV with a header written once | header only when the file is missing or empty (`[ ! -s "$HISTORY" ]`), then append |
| Threshold variable at the top | `THRESHOLD=70` |
| Reminder / no action needed | `if [ "$SCORE" -lt "$THRESHOLD" ]` writes to `/var/log/hardening-reminder.log` |
| Bonus: one copy at a time | `flock -n` on `/run/lock/hardening_check.lock` |

**What `--cronjob` changes:** it is a shortcut for `--quick --no-colors`
plus cron-friendly behaviour: Lynis never pauses to wait for Enter between
sections, prints no colour codes (which would fill a log with `^[[1;32m`
junk), and keeps screen output minimal. Without it, the audit would sit
forever waiting for a key press that no one is there to give.

One extra safety step: the script deletes the old `/var/log/lynis-report.dat`
before running Lynis. Otherwise, if Lynis failed part-way, the script could
read *yesterday's* score from the stale file and record it as today's.

---

## 3. Test by hand

```bash
sudo /usr/local/sbin/hardening_check.sh          # THRESHOLD=70, score 57 -> reminder
sudo sed -i 's/^THRESHOLD=70/THRESHOLD=50/' /usr/local/sbin/hardening_check.sh
sudo /usr/local/sbin/hardening_check.sh          # THRESHOLD=50, score 57 -> no action
sudo sed -i 's/^THRESHOLD=50/THRESHOLD=70/' /usr/local/sbin/hardening_check.sh
sudo cat /var/log/hardening-history.csv
sudo cat /var/log/hardening-reminder.log
```

📸
```
2026-11-15 06:17:25 hardening check finished, score=57 threshold=70
2026-11-15 06:18:23 hardening check finished, score=57 threshold=50
```

`/var/log/hardening-history.csv` — one header, then one row per run:

```
date,time,score
2026-11-15,06:17:25,57
2026-11-15,06:18:23,57
```

`/var/log/hardening-reminder.log` — both branches proven:

```
2026-11-15 06:17:25 REMINDER: hardening index is 57, below the threshold of 70. Review /var/log/lynis-report.dat and apply the suggestions.
2026-11-15 06:18:23 OK: hardening index is 57 (threshold 50). No action is needed.
```

---

## 4. Schedule it with cron

Create `/etc/cron.d/hardening-check` (no dot in the name), every 5 minutes for
testing:

```bash
echo '*/5 * * * * root /usr/local/sbin/hardening_check.sh >> /var/log/hardening-cron.log 2>&1' | sudo tee /etc/cron.d/hardening-check
sudo chown root:root /etc/cron.d/hardening-check
sudo chmod 644 /etc/cron.d/hardening-check
ls -l /etc/cron.d/hardening-check
```

```
-rw-r--r-- 1 root root 155 Nov 15 06:20 /etc/cron.d/hardening-check
```

After two runs (06:25 and 06:30):

```bash
sudo cat /var/log/hardening-cron.log
sudo tail -n 3 /var/log/hardening-history.csv
```

📸
```
2026-11-15 06:25:01 hardening check finished, score=59 threshold=70
2026-11-15 06:30:01 hardening check finished, score=59 threshold=70
```

```
2026-11-15,06:19:22,57
2026-11-15,06:25:01,59
2026-11-15,06:30:01,59
```

The rows are stamped exactly on the 5-minute marks, which shows cron started
them, not a person. (On my machine the runs started by cron scored 59 and the
runs I started by hand scored 57. I did not track down which Lynis test
accounts for the 2 points; if you see the same on your VM, compare the two
`/var/log/lynis-report.dat` files to find out.)

Then change the schedule to once a day at 07:00:

```bash
sudo sed -i 's|^\*/5 \* \* \* \*|0 7 * * *|' /etc/cron.d/hardening-check
cat /etc/cron.d/hardening-check
```

```
0 7 * * * root /usr/local/sbin/hardening_check.sh >> /var/log/hardening-cron.log 2>&1
```

Cron notices the changed file by itself; no restart is needed.

---

## 5. Troubleshoot

Confirm cron really ran the job:

```bash
sudo journalctl -u cron --since "30 min ago"
# or
grep CRON /var/log/syslog
```

📸 Take this screenshot on your VM. You should see lines like:

```
CRON[1234]: (root) CMD (/usr/local/sbin/hardening_check.sh >> /var/log/hardening-cron.log 2>&1)
```

> I could not capture this one: my test machine was a container without
> systemd or a syslog daemon, so cron had nowhere to write these lines. The
> proof that cron ran there is the cron log and the CSV rows above.

If the job does not appear, check in this order:

1. Is cron running? `systemctl status cron`
2. File name has no dot, owner is root, mode is 644? `ls -l /etc/cron.d/`
3. Is the `root` user field present, and does the file end with a newline?
4. Is the script executable? `ls -l /usr/local/sbin/hardening_check.sh`
5. What did the script say? `cat /var/log/hardening-cron.log`

---

## 6. Questions

### Explain the five time fields. What do `*`, `*/5` and `0 7 * * 1-5` mean?

The fields are, in order: **minute** (0–59), **hour** (0–23), **day of month**
(1–31), **month** (1–12) and **day of week** (0–7, Sunday is 0 or 7). A job
runs when the current time matches all of them.

- `*` means "every value" of that field. `* * * * *` runs every minute.
- `*/5` is a step: every 5th value. In the minute field it means minutes
  0, 5, 10 … 55, so `*/5 * * * *` runs every five minutes.
- `0 7 * * 1-5` means minute 0, hour 7, any day of the month, any month,
  Monday to Friday: **07:00 on weekdays only**.

Other forms: lists (`1,15`), ranges (`9-17`), and a range with a step
(`0-30/10`).

### Why do cron jobs need absolute paths?

Cron does not load your login shell, so there is no `.bashrc` or `.profile`.
`PATH` is usually just `/usr/bin:/bin`, and the working directory is the
user's home directory, not the folder the script lives in.

What can go wrong:

- **Command not found.** `lynis` is in `/usr/sbin`, which is not in cron's
  PATH. The script works when you test it by hand and fails silently at 07:00.
- **Files land in the wrong place.** A relative path like `history.csv` is
  created in whatever the current directory happens to be.
- **The wrong program runs.** If a script running as root relies on PATH and
  an attacker can put a file named `grep` in a directory that comes earlier
  in PATH, root runs the attacker's program. Absolute paths remove that risk.

### Why redirect output to a log file?

By default cron collects anything the job prints and tries to **email it to
the job's owner** (or the `MAILTO` address). On most servers no mail system is
installed, so the output is thrown away. You then have no idea whether the job
worked, failed, or ran at all. Even where mail works, root's mailbox fills
with messages nobody reads.

`>> /var/log/hardening-cron.log 2>&1` appends both normal output and errors to
one file that you can read later. `>>` keeps the history (a single `>` would
overwrite it on every run) and `2>&1` sends error messages to the same place.

### Why should a root-owned security script not be writable by other users?

Cron runs the script **as root**. Whoever can edit the file decides what root
runs. An attacker with a normal account who could write to it could:

- add a line that creates a new admin user, adds an SSH key to root, or opens
  a reverse shell, then simply wait for cron to run it (privilege escalation
  from normal user to root, with persistence);
- make the script always report a high score, so the reminder never fires and
  the real weakening of the system goes unnoticed.

The same applies to the directory the script is in and to the file in
`/etc/cron.d/`. If the directory were writable, the attacker could replace the
script even without write permission on the file itself. That is why the
script is `root:root 700` in `/usr/local/sbin` and the cron file is
`root:root 644`.

### What does a hardening index tell you, and what does it not tell you?

**It tells you** how many of Lynis's hardening checks this system passes,
weighted into a number from 0 to 100. It is a quick measure of how much
hardening work has been done on the configuration: password policy, kernel
settings, logging, installed security tools and so on.

**It does not tell you:**

- that the system is secure. A machine can score 85 and still have a weak
  password or a vulnerable web application, because Lynis does not test those;
- that it is compliant with any standard. It is not a percentage of "secure";
- which problems matter. A missing login banner and a missing firewall are
  both just points. The score has no idea what the machine is used for;
- anything outside the host: network design, cloud settings, users' behaviour;
- a figure you can compare between different machines or Lynis versions,
  because the set of tests that run changes with what is installed.

**Why the trend matters more:** one score is a snapshot with no context: is 62
good? For the same machine over time, the question becomes simple. A rising
line shows hardening work is paying off. A sudden drop shows something
changed: a package was installed, a setting was reverted, or someone weakened
the system. That drop is the signal worth investigating, and you can only see
it if you keep a history. That is the reason for the CSV file.

---

## 7. Bonus: real-life hardening

### Fixes applied

I applied three suggestions from `/var/log/lynis-report.dat`, running the
script after each one so I could see which change moved the score.

List the suggestions with:

```bash
sudo grep -E '^(suggestion|warning)\[\]' /var/log/lynis-report.dat | cut -d'|' -f1-2
```

**Fix 1 — legal banner (BANN-7126, BANN-7130)**

```bash
B='Authorized users only. All activity on this system is monitored and logged. Unauthorized access is prohibited and may be prosecuted.'
echo "$B" | sudo tee /etc/issue /etc/issue.net
sudo /usr/local/sbin/hardening_check.sh
```

**Fix 2 — password policy and default umask in `/etc/login.defs`
(AUTH-9286, AUTH-9328, AUTH-9230)**

```bash
sudo sed -i -e 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\t90/' \
            -e 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS\t1/' \
            -e 's/^UMASK.*/UMASK\t\t027/' \
            -e 's/^#SHA_CRYPT_MIN_ROUNDS.*/SHA_CRYPT_MIN_ROUNDS 5000/' \
            -e 's/^#SHA_CRYPT_MAX_ROUNDS.*/SHA_CRYPT_MAX_ROUNDS 10000/' /etc/login.defs
sudo /usr/local/sbin/hardening_check.sh
```

**Fix 3 — package updates (warning PKGS-7392, "vulnerable packages found")**

```bash
sudo apt update && sudo apt upgrade -y
sudo /usr/local/sbin/hardening_check.sh
```

### The score in the CSV

📸
```
date,time,score
2026-11-15,06:17:25,57      <- baseline (by hand)
2026-11-15,06:18:23,57
2026-11-15,06:19:22,57
2026-11-15,06:25:01,59      <- cron run
2026-11-15,06:30:01,59      <- cron run
2026-11-15,06:31:25,58      <- after fix 1 (banner)
2026-11-15,06:32:27,62      <- after fix 2 (login.defs)
2026-11-15,06:33:55,62      <- after fix 3 (updates)
```

(The annotations are mine; the file contains only the three columns.)

Compare runs started the same way: by hand the score went **57 → 58 → 62 → 62**.

### Which changes improved it, and why

- **Banner: +1.** Lynis checks that `/etc/issue` and `/etc/issue.net` contain
  legal wording. A banner stops nobody technically, but it removes the "I did
  not know I was not allowed" defence and is required by many policies.
- **`login.defs`: +4, the biggest gain.** This one edit satisfied several
  tests at once: passwords now expire after 90 days, cannot be changed again
  within a day (which stops cycling straight back to the old password), new
  files are created unreadable by "other" users (umask 027), and password
  hashes use a set number of rounds, which slows down cracking.
- **Package updates: +0 on the score, but the most valuable fix.** The
  `PKGS-7392` *warning* ("found one or more vulnerable packages") disappeared
  from the report, yet the index stayed at 62. Known vulnerabilities were
  actually removed from the machine and the number did not move, while a text
  banner earned a point. This is a live example of the answer above: the
  index measures checks passed, not real risk.

After the fixes, none of BANN-7126, BANN-7130, AUTH-9230, AUTH-9286, AUTH-9328
or PKGS-7392 appear in the report any more.

### Protection against two copies running (`flock`)

A Lynis audit takes about a minute here; on a slow machine a run could still
be going when cron starts the next one. Two audits writing the same report
file at the same time could produce a corrupt score.

`flock` puts a lock on a file. The script opens a lock file and asks for an
exclusive lock without waiting (`-n`). If another copy already holds it, the
new copy logs an error and exits. The kernel releases the lock when the
script ends, even if it crashes, so a stale lock can never block future runs
(a common problem with home-made "PID file" locks).

```bash
exec 9>"$LOCKFILE"
if ! $FLOCK -n 9; then
    log_error "another copy is already running, exiting"
    exit 1
fi
```

Test — start one copy in the background and a second straight after:

```bash
sudo /usr/local/sbin/hardening_check.sh &
sleep 2; sudo /usr/local/sbin/hardening_check.sh; echo "second exit=$?"
```

📸
```
2026-11-15 06:19:24 ERROR: another copy is already running, exiting
second exit=1
2026-11-15 06:19:22 hardening check finished, score=57 threshold=50
```

Only one row was added to the CSV for that pair.

---

## Appendix A: all commands used

```bash
# Set up
sudo apt update && sudo apt install lynis
lynis show version
sudo lynis audit system
sudo grep hardening_index /var/log/lynis-report.dat

# Install the script
sudo install -o root -g root -m 700 hardening_check.sh /usr/local/sbin/hardening_check.sh
ls -l /usr/local/sbin/hardening_check.sh

# Test by hand, both branches
sudo /usr/local/sbin/hardening_check.sh
sudo sed -i 's/^THRESHOLD=70/THRESHOLD=50/' /usr/local/sbin/hardening_check.sh
sudo /usr/local/sbin/hardening_check.sh
sudo sed -i 's/^THRESHOLD=50/THRESHOLD=70/' /usr/local/sbin/hardening_check.sh
sudo cat /var/log/hardening-history.csv
sudo cat /var/log/hardening-reminder.log
sudo tail /root/lynis-last-run.log

# Cron
echo '*/5 * * * * root /usr/local/sbin/hardening_check.sh >> /var/log/hardening-cron.log 2>&1' | sudo tee /etc/cron.d/hardening-check
sudo chown root:root /etc/cron.d/hardening-check
sudo chmod 644 /etc/cron.d/hardening-check
ls -l /etc/cron.d/hardening-check
sudo cat /var/log/hardening-cron.log
sudo tail -n 3 /var/log/hardening-history.csv
sudo sed -i 's|^\*/5 \* \* \* \*|0 7 * * *|' /etc/cron.d/hardening-check

# Troubleshoot
sudo journalctl -u cron --since "30 min ago"
grep CRON /var/log/syslog
systemctl status cron

# Bonus
sudo grep -E '^(suggestion|warning)\[\]' /var/log/lynis-report.dat | cut -d'|' -f1-2
echo "$B" | sudo tee /etc/issue /etc/issue.net
sudo sed -i -e ... /etc/login.defs          # full command in section 7
sudo apt update && sudo apt upgrade -y
sudo /usr/local/sbin/hardening_check.sh &
sleep 2; sudo /usr/local/sbin/hardening_check.sh; echo "second exit=$?"
```

## Appendix B: final script

See [`hardening_check.sh`](hardening_check.sh) in this folder. Paste it here
in full, with a screenshot of `cat /usr/local/sbin/hardening_check.sh`, when
you build the final answer document.

## Appendix C: final cron file

`/etc/cron.d/hardening-check` — see [`hardening-check.cron`](hardening-check.cron):

```
0 7 * * * root /usr/local/sbin/hardening_check.sh >> /var/log/hardening-cron.log 2>&1
```
