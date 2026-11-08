#!/usr/bin/env bash
# supervisor.sh [--once]   Keeps the factory moving without anyone watching. One round every 2 minutes; DRY=1 only logs.
#
#  1. RELEASE FIRST. While a delivery runs or waits, nothing is touched (quiet.sh owns the pauses). Otherwise at most
#     MAX_FIX_RUNS fix runs go at a time, and new builds run only when no fix run exists: a release is always worth more
#     than a new story. A run whose process tree holds the heavy lock is never stopped (that would block everybody).
#  2. PARK. A story in its fix loop for PARK_AFTER_MIN is parked (marker, run killed, owner notified): one stubborn story
#     must not hold the whole queue. Its worktree and branch stay. `factory unpark <story>` gives it back.
#  3. RE-DELIVER. A built story whose delivery failed and that nobody is working on is delivered again, at most
#     REDELIVER_MAX times per window (the window renews: attempts spent on infrastructure failures must not park a
#     story for good).
#  4. STALL WATCHDOG. No release for RELEASE_STALL_MIN while stories wait: log, notify, clear the counters, re-deliver.
#  5. HEAVY WATCHDOG. A heavy job (gate, E2E) held too long is warned about and then killed so the queue moves; a
#     targeted E2E gets a much lower limit than the critical set (it takes minutes; 45 minutes means it loops).
#  6. LANES. A lane driver that died abnormally is restarted from its queue file (queues/<lane>.txt).
# Everything goes to state/supervisor.log. Processes are found ONLY through pid files, never by name.
. "$(dirname "$0")/lib/common.sh"
DRY=${DRY:-}
act() { [ "$DRY" = 1 ] || "$@"; }

holds_heavy_lock() {  # holds_heavy_lock <pid>: is the heavy-lock holder this pid or one of its descendants?
  local a; a=$(cat "$HEAVY_LOCK/pid" 2>/dev/null)
  while [ -n "$a" ] && [ "$a" -gt 1 ] 2>/dev/null; do [ "$a" = "$1" ] && return 0; a=$(ps -o ppid= -p "$a" 2>/dev/null | tr -d ' '); done
  [ -d "$HEAVY_LOCK" ] && [ ! -f "$HEAVY_LOCK/pid" ] && return 0     # the lock is being taken right now
  return 1
}
set_run_state() {  # set_run_state <kind> <story> <pid> <run|stop>
  local st; st=$(proc_state "$3"); [ -n "$st" ] || return 0
  if [ "$4" = stop ] && [ "$st" != T ]; then
    holds_heavy_lock "$3" && return 0
    say "PAUSED $1 run of $2 (pid $3): release first"; act pause_tree "$3"
  elif [ "$4" = run ] && [ "$st" = T ]; then
    say "RESUMED $1 run of $2 (pid $3)"; act resume_tree "$3"
  fi
}
delivery_active() {
  local f
  for f in "$HEAVY_LOCK".prio.*; do [ -e "$f" ] && pid_alive "${f##*.}" && return 0; done
  [ -n "$(list_runs deliver)" ] && return 0
  return 1
}
unreleased_waiting() {  # stories whose delivery failed and that are not released/parked, one per line
  grep -E "^[^ ]+ (DELIVERY-FAILED|CRITICAL-E2E-FAILED) " "$LOG" 2>/dev/null | awk '{print $1}' | sort -u | while read -r s; do
    story_done "$s" && continue; story_parked "$s" && continue; [ -d "$(story_wt "$s")" ] || continue; echo "$s"
  done
}
being_worked() {  # a live driver, fix run or delivery for the story
  local o; o=$(cat "$STATE_DIR/.run.$1" 2>/dev/null)
  pid_alive "$o" && return 0
  pid_running fix "$1" && return 0; pid_running deliver "$1" && return 0; pid_running build "$1" && return 0
  return 1
}

round() {
  local name pid fixes builds k want
  # 1. release first
  if ! delivery_active; then
    fixes=$(list_runs fix | sort -k2 -n); builds=$(list_runs build | sort -k2 -n)
    k=0
    echo "$fixes" | while read -r name pid; do
      [ -n "$name" ] || continue; k=$((k + 1)); want=run; [ $k -gt "$MAX_FIX_RUNS" ] && want=stop
      set_run_state fix "$name" "$pid" "$want"
    done
    echo "$builds" | while read -r name pid; do
      [ -n "$name" ] || continue; want=run; [ -n "$fixes" ] && want=stop
      set_run_state build "$name" "$pid" "$want"
    done
  fi
  # 2. park
  list_runs fix | while read -r name pid; do
    [ -n "$name" ] || continue
    [ -f "$STATE_DIR/.fixing.$name" ] || : > "$STATE_DIR/.fixing.$name"
    if story_parked "$name"; then
      say "killed fix run of parked story $name"; act kill_tree "$pid" TERM
    elif [ "$(file_age_min "$STATE_DIR/.fixing.$name")" -ge "$PARK_AFTER_MIN" ]; then
      : > "$STATE_DIR/.parked.$name"; say "PARKED $name after ${PARK_AFTER_MIN}min in the fix loop"
      log_event "$name" PARKED "after ${PARK_AFTER_MIN}min in the fix loop (worktree kept; needs a look)"
      notify "$name is parked: its fix loop ran ${PARK_AFTER_MIN} min without delivering. Worktree kept."
      act kill_tree "$pid" TERM
    fi
  done
  for f in "$STATE_DIR"/.fixing.*; do [ -e "$f" ] || continue; n=${f##*.fixing.}; story_done "$n" && rm -f "$f"; done
  # 3. re-deliver
  local s n
  for s in $(unreleased_waiting); do
    being_worked "$s" && continue
    [ -d "$STATE_DIR/deliver.lock" ] && continue
    if [ -f "$STATE_DIR/.redeliver.$s" ] && [ "$(file_age_min "$STATE_DIR/.redeliver.$s")" -ge "$REDELIVER_WINDOW_MIN" ]; then rm -f "$STATE_DIR/.redeliver.$s"; fi
    n=$(cat "$STATE_DIR/.redeliver.$s" 2>/dev/null || echo 0)
    [ "$n" -ge "$REDELIVER_MAX" ] && continue
    say "REDELIVER $s (attempt $((n + 1)))"
    [ "$DRY" = 1 ] && continue
    echo $((n + 1)) > "$STATE_DIR/.redeliver.$s"
    (cd "$FACTORY_BIN" && nohup ./drive.sh "$s" > "$RUNS/drive-$s.redeliver.out" 2>&1 < /dev/null &)
    break
  done
  # 4. stall watchdog
  local count stamp_count stamp_time age waiting
  count=$(grep -cE "^[^ ]+ RELEASED " "$LOG" 2>/dev/null); count=${count:-0}   # grep -c prints 0 AND fails: never "|| echo 0"
  if [ -f "$STATE_DIR/.release-stamp" ]; then read -r stamp_count stamp_time < "$STATE_DIR/.release-stamp"; else stamp_count=-1; stamp_time=$(now); fi
  case "$stamp_time" in ''|*[!0-9]*) stamp_count=-1; stamp_time=$(now) ;; esac
  if [ "$count" != "$stamp_count" ]; then echo "$count $(now)" > "$STATE_DIR/.release-stamp"; stamp_time=$(now); fi
  age=$(( ($(now) - stamp_time) / 60 )); waiting=$(unreleased_waiting | wc -l | tr -d ' ')
  if [ "$age" -ge "$RELEASE_STALL_MIN" ] && [ "$waiting" -gt 0 ] && ! delivery_active; then
    say "STALL no release for ${age}min, $waiting stories waiting; stack-start failures: $(grep -l 'stack did not start' "$RUNS"/*.merge 2>/dev/null | wc -l | tr -d ' ')"
    log_event lane STALL "no release for ${age}min, $waiting waiting"; notify "Factory stall: no release for ${age} min, $waiting stories waiting"
    if [ "$DRY" != 1 ]; then
      rm -f "$STATE_DIR"/.redeliver.*
      for s in $(unreleased_waiting); do being_worked "$s" && continue; say "STALL-REDELIVER $s"; (cd "$FACTORY_BIN" && nohup ./deliver.sh "$s" > "$RUNS/drive-$s.redeliver.out" 2>&1 < /dev/null &); break; done
    fi
  fi
  # 5. heavy watchdog
  if [ -f "$HEAVY_LOCK/pid" ]; then
    local hp mins limit what
    hp=$(cat "$HEAVY_LOCK/pid"); mins=$(etime_min "$hp") || mins=""
    if [ -n "$mins" ]; then
      what=$(cat "$HEAVY_LOCK/what" 2>/dev/null | tr 'A-Z' 'a-z'); limit=$HEAVY_LIMIT_MIN
      case "$what" in *critical*|*gate*|*full*) ;; *e2e*|*playwright*|*cypress*|*spec*) limit=$HEAVY_TARGETED_LIMIT_MIN ;; esac
      if [ "$mins" -ge "$limit" ]; then
        say "STUCK heavy job pid $hp for ${mins}min (limit ${limit}): killing: $what"; log_event lane HEAVY-KILLED "${mins}min: $what"
        act kill_tree "$hp" TERM; [ "$DRY" = 1 ] || { sleep 10; kill_tree "$hp" KILL; }
      elif [ "$mins" -ge "$HEAVY_WARN_MIN" ]; then say "STUCK? heavy job pid $hp for ${mins}min: $what"; fi
    fi
  fi
  # 6. lanes
  local q lane ids
  for q in "$FACTORY_DIR"/queues/*.txt; do
    [ -e "$q" ] || continue
    lane=$(basename "$q" .txt)
    # queue CONTENT changed since the lane finished: run again (content, not mtime: a checkout rewrites mtimes without edits)
    if [ -f "$STATE_DIR/lane-$lane.done" ] && [ "$(cksum < "$q")" != "$(cat "$STATE_DIR/lane-$lane.done" 2>/dev/null)" ]; then
      [ -s "$STATE_DIR/lane-$lane.done" ] && rm -f "$STATE_DIR/lane-$lane.done"
      [ -f "$STATE_DIR/lane-$lane.done" ] && cksum < "$q" > "$STATE_DIR/lane-$lane.done"   # old empty marker: adopt the current content
    fi
    pid_running lane "$lane" && continue
    [ -f "$STATE_DIR/lane-$lane.done" ] && continue
    [ -f "$STATE_DIR/lane-$lane.stopped" ] && continue
    ids=$(grep -v '^[[:space:]]*#' "$q" | grep -v '^[[:space:]]*$' | awk '{print $1}' | tr '\n' ' ')
    [ -n "$ids" ] || continue
    say "LANE $lane is not running: starting it"; log_event lane LANE-START "$lane"
    # shellcheck disable=SC2086
    [ "$DRY" = 1 ] || (cd "$FACTORY_BIN" && nohup ./drive.sh --lane "$lane" $ids > "$RUNS/lane-$lane.out" 2>&1 < /dev/null &)
  done
  # 7. a push of the integration branch that was refused (PUSH-PENDING) is retried when nothing is delivering
  if ! delivery_active && git -C "$REPO" rev-parse -q --verify "refs/remotes/$REMOTE/$INTEGRATION_BRANCH" >/dev/null 2>&1; then
    if [ "$(git -C "$REPO" rev-parse "$INTEGRATION_BRANCH" 2>/dev/null)" != "$(git -C "$REPO" rev-parse "refs/remotes/$REMOTE/$INTEGRATION_BRANCH")" ] \
       && git -C "$REPO" merge-base --is-ancestor "refs/remotes/$REMOTE/$INTEGRATION_BRANCH" "$INTEGRATION_BRANCH" 2>/dev/null; then
      if [ "$DRY" != 1 ] && lock_take "$DELIVER_LOCK" 30; then
        if [ "$(git -C "$REPO" branch --show-current)" = "$INTEGRATION_BRANCH" ] && git -C "$REPO" push -q "$REMOTE" "$INTEGRATION_BRANCH" >/dev/null 2>&1; then
          say "PUSHER integration branch pushed"; log_event lane PUSHER "pushed $(git -C "$REPO" rev-parse --short "$INTEGRATION_BRANCH")"
        else say "PUSHER push still refused"; fi
        lock_release "$DELIVER_LOCK"
      fi
    fi
  fi
  # disk
  local f; f=$(free_gb)
  if [ -n "$f" ] && [ "$f" -lt "$DISK_CRITICAL_GB" ]; then notify "Factory disk is critically low: ${f} GB free"; log_event lane LOW-DISK "${f} GB"; fi
}
if [ "${1:-}" = "--once" ]; then round; exit 0; fi
# single instance: two copies would double every action (seen when two coordinator sessions both "restarted" it)
other=$(pid_of lane supervisor); if pid_alive "$other" && [ "$other" != "$$" ]; then echo "supervisor already running (pid $other)"; exit 0; fi
pid_register lane supervisor
trap 'pid_unregister lane supervisor' EXIT
while true; do round; sleep 120; done
