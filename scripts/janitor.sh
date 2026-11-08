#!/usr/bin/env bash
# janitor.sh [--once]   Keeps the machine from filling up during unattended builds. Every 2 minutes:
#   - logs free disk and memory;
#   - below DISK_LOW_GB: removes the docker volumes of story stacks that no running container uses and whose worktree is
#     gone, dangling images, and (below DISK_CRITICAL_GB) the build cache; runs CMD_CACHE_TRIM (the project's own safe
#     trim of build caches: it must be safe while builds run, because a "run only when idle" trim never runs when the
#     factory is never idle - a 95 GB cache once filled a disk this way);
#   - removes finished worktrees (branch already in the integration branch, nothing uncommitted, no live run) with
#     their stack;
#   - stops verification stacks left over from earlier critical runs (each costs gigabytes of RAM).
# It never touches other projects' containers or volumes: it only handles names that start with STACK_NAME_PREFIX, never
# the demo stack (name contains -demo), and never a stack whose story worktree still exists.
. "$(dirname "$0")/lib/common.sh"
JLOG="$STATE_DIR/janitor.log"

stack_protected() {  # volume or container name -> 0 when it must stay
  local n=$1 wt
  case "$n" in *-demo*) return 0 ;; esac
  for wt in "$WORKTREES"/*; do
    [ -d "$wt" ] || continue
    case "$(basename "$wt")" in verify-*) continue ;; esac
    export_stack_env "$(basename "$wt")" "$wt"
    case "$n" in "$FACTORY_STACK_NAME"[-_]*|"$FACTORY_STACK_NAME") return 0 ;; esac
  done
  return 1
}
clean_docker() {
  [ "$STACK_ENGINE" = docker ] || return 0
  local v
  timeout 60 docker volume ls -q 2>/dev/null | grep "^${STACK_NAME_PREFIX}-" | while read -r v; do
    stack_protected "$v" || timeout 60 docker volume rm "$v" >/dev/null 2>&1
  done
  timeout 120 docker image prune -f >/dev/null 2>&1
  [ "$(free_gb)" -lt "$DISK_CRITICAL_GB" ] && timeout 300 docker builder prune -af >/dev/null 2>&1
  return 0
}
sweep_worktrees() {
  local d n br
  for d in "$WORKTREES"/*; do
    [ -d "$d" ] || continue
    n=$(basename "$d"); case "$n" in verify-*|"*") continue ;; esac
    [ -e "$d/.git" ] || continue
    br=$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null); case "$br" in "${STORY_BRANCH_PREFIX}"*) ;; *) continue ;; esac
    pid_running build "$n" && continue; pid_running fix "$n" && continue; pid_running deliver "$n" && continue
    [ -z "$(git -C "$d" status --porcelain 2>/dev/null)" ] || continue
    git -C "$REPO" merge-base --is-ancestor "$br" "$INTEGRATION_BRANCH" 2>/dev/null || continue
    export_stack_env "$n" "$d"; [ -n "$CMD_STACK_DOWN" ] && run_cmd "$CMD_STACK_DOWN" "$d" >/dev/null 2>&1
    git -C "$REPO" worktree remove --force "$d" >/dev/null 2>&1 || rm -rf "$d"
    git -C "$REPO" worktree prune; git -C "$REPO" branch -d "$br" >/dev/null 2>&1 || true
    echo "$(ts) removed finished worktree $n" >> "$JLOG"
  done
}
stale_verify_stacks() {
  [ "$STACK_ENGINE" = docker ] || return 0
  case "$(cat "$HEAVY_LOCK/what" 2>/dev/null)" in *critical*|*verify*) return 0 ;; esac   # a verification is running
  [ -n "$(list_runs deliver)" ] && return 0
  stop_containers "$VERIFY_STACK_PREFIX"
}
round() {
  local f; f=$(free_gb)
  echo "$(ts) free ${f}G, memory free $(mem_free_gb)G" >> "$JLOG"
  if [ -n "$f" ] && [ "$f" -lt "$DISK_LOW_GB" ]; then
    clean_docker
    [ -n "$CMD_CACHE_TRIM" ] && run_cmd "$CMD_CACHE_TRIM" "$REPO" >/dev/null 2>&1
    echo "$(ts) cleaned; free $(free_gb)G" >> "$JLOG"
  fi
  [ "$(free_gb)" -lt 6 ] && { log_event lane LOW-DISK "$(free_gb)G"; notify "Factory disk is almost full: $(free_gb) GB free"; }
  sweep_worktrees
  stale_verify_stacks
}
if [ "${1:-}" = "--once" ]; then round; exit 0; fi
# single instance: two copies would double every action (seen when two coordinator sessions both "restarted" it)
other=$(pid_of lane janitor); if pid_alive "$other" && [ "$other" != "$$" ]; then echo "janitor already running (pid $other)"; exit 0; fi
pid_register lane janitor
trap 'pid_unregister lane janitor' EXIT
while :; do round; sleep 120; done
