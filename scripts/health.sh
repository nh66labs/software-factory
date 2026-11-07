#!/usr/bin/env bash
# health.sh [--fix] [--short]   One-shot health report; exit 0 healthy, 1 degraded, 2 broken.
# This is the check the coordinating agent runs on a schedule (every 30 minutes) and acts on WITHOUT asking. Tag meaning:
#   OK    nothing to do        INFO  state worth knowing        WARN  act soon        FAIL  broken, act now
# --fix repairs what is safe to repair: restarts a dead supervisor/janitor, removes stale locks, starts idle lanes.
# Rule for the reader: say nothing when everything is OK; tell the owner when a release went out or when something broke
# that could not be fixed. Fix first, report after.
. "$(dirname "$0")/lib/common.sh"
FIX=0; SHORT=0
for a in "$@"; do case "$a" in --fix) FIX=1 ;; --short) SHORT=1 ;; esac; done
worst=0
out() { local tag=$1; shift; echo "$tag $*"; case "$tag" in WARN) [ $worst -lt 1 ] && worst=1 ;; FAIL) worst=2 ;; esac; }

# daemons
for d in supervisor janitor; do
  if pid_running lane "$d"; then out OK "$d running (pid $(pid_of lane "$d"))"
  else
    out FAIL "$d is not running"
    if [ $FIX = 1 ]; then
      (cd "$FACTORY_BIN" && nohup "./$d.sh" > "$STATE_DIR/$d.out" 2>&1 < /dev/null &); out INFO "$d restarted"
    fi
  fi
done
# lanes and runs
nb=$(list_runs build | wc -l | tr -d ' '); nf=$(list_runs fix | wc -l | tr -d ' ')
paused=0; for k in build fix; do for p in $(list_runs $k | awk '{print $2}'); do [ "$(proc_state "$p")" = T ] && paused=$((paused + 1)); done; done
out INFO "runs: $nb building, $nf fixing, $paused paused"
for q in "$FACTORY_DIR"/queues/*.txt; do
  [ -e "$q" ] || continue; lane=$(basename "$q" .txt)
  grep -qv '^[[:space:]]*\(#.*\)\{0,1\}$' "$q" || continue   # an empty queue is not a lane
  if pid_running lane "$lane"; then out OK "lane $lane running"
  elif [ -f "$STATE_DIR/lane-$lane.done" ]; then out INFO "lane $lane finished its queue"
  elif [ -f "$STATE_DIR/lane-$lane.stopped" ]; then out INFO "lane $lane is stopped on purpose"
  else out WARN "lane $lane is not running (the supervisor restarts it within 2 minutes)"; fi
done
# releases
rel=$(grep -E "^[^ ]+ RELEASED " "$LOG" 2>/dev/null | tail -1)
if [ -n "$rel" ]; then
  stamp=$(sed -n 's/.* \([0-9-]\{10\} [0-9:]\{5\}\)$/\1/p' <<<"$rel")
  out INFO "last release: ${rel%% to production*} at $stamp"
fi
if [ -f "$STATE_DIR/.release-stamp" ]; then
  read -r _c t < "$STATE_DIR/.release-stamp"; case "$t" in ''|*[!0-9]*) t=$(now) ;; esac; age=$(( ($(now) - t) / 60 ))
  w=$(grep -E "^[^ ]+ (DELIVERY-FAILED|CRITICAL-E2E-FAILED) " "$LOG" 2>/dev/null | awk '{print $1}' | sort -u | while read -r s; do story_done "$s" || story_parked "$s" || echo "$s"; done | tr '\n' ' ')
  if [ "$age" -ge "$RELEASE_STALL_MIN" ] && [ -n "$w" ]; then out FAIL "no release for ${age} min while these wait: $w"; else out OK "release age ${age} min; waiting for delivery: ${w:-none}"; fi
fi
parked=$(ls "$STATE_DIR"/.parked.* 2>/dev/null | sed 's/.*\.parked\.//' | tr '\n' ' ')
[ -n "$parked" ] && out WARN "parked stories (need a look): $parked"
# unreleased commits
if git -C "$REPO" rev-parse -q --verify "$PRODUCTION_BRANCH" >/dev/null 2>&1 && [ "$PRODUCTION_BRANCH" != "$INTEGRATION_BRANCH" ]; then
  n=$(git -C "$REPO" rev-list --count "$PRODUCTION_BRANCH..$INTEGRATION_BRANCH" 2>/dev/null || echo 0)
  [ "$n" -gt 0 ] && out INFO "$n commit(s) on $INTEGRATION_BRANCH not yet in production"
fi
# heavy lock
if [ -f "$HEAVY_LOCK/pid" ]; then
  hp=$(cat "$HEAVY_LOCK/pid"); m=$(etime_min "$hp") || m="?"
  out INFO "heavy lock held ${m} min by pid $hp: $(cat "$HEAVY_LOCK/what" 2>/dev/null | cut -c1-90)"
  if [ "$m" != "?" ] && [ "$m" -ge "$HEAVY_LIMIT_MIN" ]; then out FAIL "heavy job over the limit (${HEAVY_LIMIT_MIN} min); the supervisor kills it"; fi
fi
# machine
f=$(free_gb)
if [ -n "$f" ]; then
  if [ "$f" -lt "$DISK_CRITICAL_GB" ]; then out FAIL "disk ${f} GB free"; elif [ "$f" -lt "$DISK_LOW_GB" ]; then out WARN "disk ${f} GB free (janitor cleaning)"; else out OK "disk ${f} GB free"; fi
fi
out INFO "memory free $(mem_free_gb) GB of $(mem_total_gb) GB; cpus $(cpu_count)"
# infrastructure failures in the last hour
recent=$(grep -E "INFRA-WAIT" "$LOG" 2>/dev/null | tail -3 | tr '\n' ';' | cut -c1-200)
[ -n "$recent" ] && [ -n "$(find "$LOG" -mmin -60 2>/dev/null)" ] && out WARN "recent agent infrastructure failures (network/API/limits?): $recent"
# deploy
if [ -n "$CMD_DEPLOY_STATUS" ]; then
  if st=$(run_cmd "$CMD_DEPLOY_STATUS" "$REPO" 2>&1); then out OK "deploy: $(echo "$st" | head -1 | cut -c1-100)"; else out FAIL "deploy: $(echo "$st" | head -1 | cut -c1-100)"; fi
fi
if [ -n "$CMD_AGENT_AUTH_CHECK" ] && ! run_cmd "$CMD_AGENT_AUTH_CHECK" "$REPO" >/dev/null 2>&1; then out FAIL "the agent CLI is not logged in"; fi
# stale locks
if [ -d "$DELIVER_LOCK" ]; then
  hp=$(cat "$DELIVER_LOCK/pid" 2>/dev/null)
  if [ -n "$hp" ] && ! pid_alive "$hp"; then out WARN "stale delivery lock"; [ $FIX = 1 ] && rm -rf "$DELIVER_LOCK" && out INFO "stale delivery lock removed"; fi
fi
spent=$(spend_today); out INFO "agent spend today: \$$spent${DAILY_BUDGET_USD:+ (cap $DAILY_BUDGET_USD)}"
case $worst in 0) echo "SUMMARY healthy" ;; 1) echo "SUMMARY degraded" ;; *) echo "SUMMARY broken" ;; esac
exit $worst
