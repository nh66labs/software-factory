#!/usr/bin/env bash
# drive.sh [--lane <name>] <story-id>...   Builds the queued stories one at a time with headless agent runs, delivers
# each (rebase, critical tests on the rebased commit, integration branch, release) and cleans up. Restartable: the same
# command resumes where it stopped (finished and parked stories are skipped, a built story whose delivery failed is not
# built again).
#
# Failure handling (the part that makes it unattended):
#   INFRA     network/API down, usage limit, killed run: retried after a pause WITHOUT counting an attempt
#   BLOCKED deps ...   the story needs a story that is not built yet: moved to the back, stop when a pass makes no progress
#   other BLOCKED      retried once from the same worktree, then FAILED and the queue goes on
#   delivery failed    up to 3 short fix runs in the story's own worktree (rebase conflict, failing critical test), then
#                      DELIVERY-FAILED and the queue goes on; the supervisor re-delivers or parks it
# One driver per story (pid file), a parked story is never touched, an unknown story id is rejected before any agent
# run is paid for, and a daily budget (DAILY_BUDGET_USD) pauses the lane instead of spending past it.
. "$(dirname "$0")/lib/common.sh"
lane=""
if [ "${1:-}" = "--lane" ]; then lane=$2; shift 2; fi
queue=("$@")
[ ${#queue[@]} -gt 0 ] || { echo "usage: drive.sh [--lane <name>] <story-id>..." >&2; exit 2; }
[ -n "$lane" ] && { pid_register lane "$lane"; rm -f "$STATE_DIR/lane-$lane.done"; trap 'pid_unregister lane "$lane"' EXIT; }
deferred=(); progress=0; waited=0
DEFER_WAIT_MIN=${DEFER_WAIT_MIN:-240}; DEFER_POLL=${DEFER_POLL:-60}
others_active() {  # another lane driver, a build/fix run or a delivery is alive (not counting this driver or the daemons)
  local n p
  list_runs lane | while read -r n p; do case "$n" in supervisor|janitor|keepawake|verifier) ;; *) [ "$p" != "$$" ] && echo x ;; esac; done | grep -q . && return 0
  [ -n "$(list_runs deliver)" ] && return 0
  [ -n "$(list_runs build)" ] && return 0
  return 1
}

wait_for_stack_engine() {  # up to 15 minutes
  [ "$STACK_ENGINE" = docker ] || return 0
  local i; for i in $(seq 1 90); do docker_ok && return 0; sleep 10; done
  return 1
}
wait_for_budget() {
  budget_ok && return 0
  log_event lane BUDGET-HOLD "daily budget \$$DAILY_BUDGET_USD reached (spent \$$(spend_today))"; notify "Daily agent budget reached; lane ${lane:-?} holds"
  while ! budget_ok; do sleep 600; done
}
prompt_for() {  # prompt_for <story> <fix|build>: renders the prompt file and prints its path
  local story=$1 kind=$2 file="$RUNS/$story.$2.prompt" tpl
  export STORY=$story REPO WORKTREES INTEGRATION_BRANCH PRODUCTION_BRANCH PLAN_DIR COMMIT_TRAILERS PROTECT_PATHS_NOTE
  export CMD_GATE_FAST CMD_GATE_FULL CMD_E2E_TARGETED CMD_STACK_UP CMD_STACK_DOWN CMD_STACK_RESET E2E_VERDICT_FILE
  export PROJECT_NAME; export WORKTREE; WORKTREE=$(story_wt "$story"); export BRANCH; BRANCH=$(story_branch "$story")
  export MERGE_LOG="$RUNS/$story.merge"
  if [ "$kind" = fix ]; then
    python3 -I "$FACTORY_BIN/render-prompt.py" "$FACTORY_DIR/prompts/fix-run.md" "$FACTORY_DIR/prompts/_common.md" > "$file"
  else
    tpl="$FACTORY_DIR/prompts/$story.md"
    if [ ! -f "$tpl" ]; then
      case "$story" in SWEEP-*-*) tpl="$FACTORY_DIR/prompts/sweep.md"; EPIC=${story#SWEEP-}; export EPIC=${EPIC%-*} ;; *) tpl="$FACTORY_DIR/prompts/build-story.md" ;; esac
    fi
    python3 -I "$FACTORY_BIN/render-prompt.py" "$tpl" "$FACTORY_DIR/prompts/_common.md" > "$file"
  fi
  echo "$file"
}
agent_line() {  # agent_line <kind> <story> <prompt> <cwd> <effort>: one run; INFRA results are retried without counting
  local kind=$1 story=$2 prompt=$3 cwd=$4 effort=$5 line n=0
  while :; do
    wait_for_budget
    wait_for_stack_engine || { echo "BLOCKED stack engine is not responding"; return; }
    line=$("$FACTORY_BIN/run-agent.sh" "$kind" "$story" "$prompt" "$cwd" "$effort")
    case "$line" in
      INFRA*)
        n=$((n + 1))
        if [ $n -gt "$INFRA_RETRY_MAX" ]; then echo "BLOCKED infra: $line"; return; fi
        log_event "$story" INFRA-WAIT "$line (retry $n/$INFRA_RETRY_MAX in ${INFRA_RETRY_SLEEP}s; not counted as an attempt)"
        [ $n -eq 1 ] && notify "$story: agent runs are failing for infrastructure reasons ($line)"
        sleep "$INFRA_RETRY_SLEEP" ;;
      *) echo "$line"; return ;;
    esac
  done
}
build_story() { agent_line build "$1" "$(prompt_for "$1" build)" "$REPO" "$AGENT_EFFORT"; }
fix_story()   { agent_line fix   "$1" "$(prompt_for "$1" fix)"   "$REPO" "$AGENT_FIX_EFFORT"; }
cleanup_stack() {
  local wt; wt=$(story_wt "$1"); [ -d "$wt" ] || return 0
  export_stack_env "$1" "$wt"; [ -n "$CMD_STACK_DOWN" ] && timeout 300 sh -c "cd '$wt' && $CMD_STACK_DOWN" >/dev/null 2>&1; true
}
deliver() { "$FACTORY_BIN/deliver.sh" "$1"; }

while :; do
  for story in "${queue[@]}"; do
    story_done "$story" && continue
    if ! story_exists "$story"; then log_event "$story" FAILED "unknown story: it is not in the plan (check the id); no agent run was started"; continue; fi
    owner=$(cat "$STATE_DIR/.run.$story" 2>/dev/null)   # one driver per story: a second one would edit the same worktree
    if [ -n "$owner" ] && [ "$owner" != "$$" ] && pid_alive "$owner"; then say "$story is already driven by pid $owner: skipped"; continue; fi
    echo $$ > "$STATE_DIR/.run.$story"
    attempt=1
    while :; do
      story_parked "$story" && { say "$story is parked: not worked on"; break; }
      log_event "$story" START "attempt $attempt"
      if [ -d "$(story_wt "$story")" ] && [ "$(grep -E "^$story (DONE|DELIVERY-FAILED|RELEASED)" "$LOG" | tail -1 | awk '{print $2}')" = DELIVERY-FAILED ]; then
        line="DONE resumed"      # built before; only the delivery failed: do not build it again
      else
        line=$(build_story "$story")
      fi
      cleanup_stack "$story"
      case "$line" in
        DONE*)
          if deliver "$story"; then
            log_event "$story" DONE "${line#DONE }"; progress=1; break
          fi
          log_event "$story" REBASE-FIX "delivery stopped (conflict or failing critical test); fixing in its worktree"
          ok=0; tries=0
          while [ $tries -lt 3 ]; do
            story_parked "$story" && break
            fixed=$(fix_story "$story"); cleanup_stack "$story"
            case "$fixed" in INFRA*|"BLOCKED infra"*) continue ;; esac   # nothing learned: not a try
            tries=$((tries + 1))
            if [[ "$fixed" == DONE* ]] && deliver "$story"; then ok=1; break; fi
            log_event "$story" REBASE-FIX "attempt $tries did not deliver: $fixed"; sleep 120
          done
          if [ $ok = 1 ]; then log_event "$story" DONE "${line#DONE } (after fix run)"; progress=1; break; fi
          log_event "$story" DELIVERY-FAILED "$line / fix: ${fixed:-none} (see runs/$story.merge)"; break ;;
        "BLOCKED deps"*)
          log_event "$story" DEFERRED "$line"; deferred+=("$story"); break ;;
        *)
          cp "$RUNS/$story.build.json" "$RUNS/$story.attempt$attempt.json" 2>/dev/null
          if [ $attempt -lt 2 ]; then log_event "$story" RETRY "after: $line"; attempt=$((attempt + 1)); sleep 300
          else log_event "$story" FAILED "$line"; break; fi ;;
      esac
    done
    rm -f "$STATE_DIR/.run.$story"
  done
  if [ ${#deferred[@]} -eq 0 ]; then
    log_event lane QUEUE-EMPTY "${lane:-}"; [ -n "$lane" ] && { q="$FACTORY_DIR/queues/$lane.txt"; if [ -f "$q" ]; then cksum < "$q"; fi > "$STATE_DIR/lane-$lane.done"; }; exit 0
  fi
  if [ $progress -eq 0 ]; then
    # nothing could be built this pass. If other lanes or a delivery are still working, the missing stories may arrive:
    # wait for them (bounded) instead of giving up; otherwise the plan has a gap and a human must look.
    if others_active && [ $waited -lt $((DEFER_WAIT_MIN * 60)) ]; then
      sleep "$DEFER_POLL"; waited=$((waited + DEFER_POLL)); queue=("${deferred[@]}"); deferred=(); continue
    fi
    log_event lane STUCK "deferred: ${deferred[*]}"; [ -n "$lane" ] && { q="$FACTORY_DIR/queues/$lane.txt"; if [ -f "$q" ]; then cksum < "$q"; fi > "$STATE_DIR/lane-$lane.done"; }; exit 5
  fi
  waited=0; queue=("${deferred[@]}"); deferred=(); progress=0
done
