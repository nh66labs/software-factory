#!/usr/bin/env bash
# usage.sh [hours]   Agent cost and rate from progress.log (every finished run logs cost=$X tokens=N).
. "$(dirname "$0")/lib/common.sh"
python3 -I - "$LOG" "${1:-24}" <<'PY'
import re, sys, datetime
log, hours = sys.argv[1], float(sys.argv[2])
now = datetime.datetime.now()
total = runs = toks = 0
per_day = {}
for line in open(log, errors="replace"):
    m = re.search(r"cost=\$([\d.]+)", line)
    if not m:
        continue
    d = re.search(r"(\d{4}-\d{2}-\d{2}) (\d{2}):(\d{2})\s*$", line)
    when = datetime.datetime(int(d.group(1)[:4]), int(d.group(1)[5:7]), int(d.group(1)[8:10]), int(d.group(2)), int(d.group(3))) if d else None
    cost = float(m.group(1))
    day = d.group(1) if d else "?"
    per_day[day] = per_day.get(day, 0) + cost
    if when is None or (now - when).total_seconds() <= hours * 3600:
        total += cost; runs += 1
        t = re.search(r"tokens=(\d+)", line)
        toks += int(t.group(1)) if t else 0
print("last %gh: %d runs, $%.2f, %.0fM tokens (average $%.2f per run)" % (hours, runs, total, toks / 1e6, total / max(runs, 1)))
for day in sorted(per_day)[-7:]:
    print("  %s  $%.2f" % (day, per_day[day]))
PY
