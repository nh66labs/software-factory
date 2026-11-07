#!/usr/bin/env bash
# Shared helpers for every factory script. Source it; it loads the project's factory.conf and defines portable
# helpers (macOS and Linux, bash 3.2 compatible: no associative arrays, no mapfile, no ${var^^}).
#
#   FACTORY_DIR   the project's .factory directory (default: the parent of the scripts directory)
#   FACTORY_CONF  the configuration file (default: $FACTORY_DIR/factory.conf)
#
# Never print secrets from here. Nothing in this file is specific to a product, a stack or a machine.

[ -n "${FACTORY_COMMON_LOADED:-}" ] && return 0
FACTORY_COMMON_LOADED=1

_fac_here() { cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd; }
FACTORY_BIN=${FACTORY_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
FACTORY_DIR=${FACTORY_DIR:-$(cd "$FACTORY_BIN/.." && pwd)}
FACTORY_CONF=${FACTORY_CONF:-$FACTORY_DIR/factory.conf}
export FACTORY_BIN FACTORY_DIR   # factory.conf commands reference the scripts as "$FACTORY_BIN/..." (a fresh worktree does not contain .factory)

# ---------------------------------------------------------------- defaults (overridden by factory.conf)
PROJECT_NAME=project
REPO=                                  # the main checkout (absolute path); required
WORKTREES=                             # where story worktrees live; default: $REPO/../<repo-name>-wt
INTEGRATION_BRANCH=staging             # stories merge here after the critical tests passed on the exact commit
PRODUCTION_BRANCH=main                 # equal to INTEGRATION_BRANCH when there is a single environment
REMOTE=origin
STORY_BRANCH_PREFIX=story/             # one branch per story: story/<ID>
STATE_DIR=                             # runtime state; default: $FACTORY_DIR/state (keep it out of git)
PLAN_DIR=                              # where the plan (epics/stories) lives; used by plan checks and story lookup
AUTO_RELEASE=1                         # 1 = release to production after every delivery; 0 = stop at the integration branch

# agent runner (see adapters/): claude | codex | generic
AGENT_ADAPTER=claude
AGENT_MODEL=                           # empty = the CLI's default model
AGENT_EFFORT=medium
AGENT_FIX_EFFORT=medium
AGENT_EXTRA_FLAGS=
COMMIT_TRAILERS=                       # lines appended to every commit message the agents make, separated by \n

# commands that adapt the factory to a stack. Run inside the worktree unless noted. See references/11-adapting-to-stack.md
CMD_STACK_UP=                          # start the story's isolated stack (optional)
CMD_STACK_DOWN=                        # stop it and WIPE its data (optional)
CMD_STACK_RESET=                       # wipe and start again (used by the critical E2E for a fresh database)
CMD_GATE_FAST=                         # pre-push gate: format, lint, unit tests, plan/trace checks
CMD_GATE_FULL=                         # the full gate
CMD_E2E_TARGETED=                      # run a few E2E specs (optional, for fix runs)
CMD_E2E_CRITICAL=                      # run the critical end-to-end tests of the commit in $1; must write $E2E_VERDICT_FILE
E2E_VERDICT_FILE=                      # relative to the verification worktree; JSON: {commit, ok, passed, failed, retries, reasons}
CMD_E2E_MATRIX=                        # the full matrix, scheduled (matrix-check.sh)
CMD_DEMO_REFRESH=                      # in the main checkout: refresh the live demo/staging after a delivery (optional)
CMD_DEPLOY_STATUS=                     # print the state of the last production deploy; exit 0 = healthy (optional)
CMD_POST_RELEASE_CHECK=                # smoke check run after a release; non-zero = release suspect (optional)
CMD_STORY_EXISTS=                      # exit 0 if story id $1 exists in the plan; default: grep the plan dir for the id
CMD_AGENT_AUTH_CHECK=                  # exit 0 if the agent CLI is logged in (optional)
NOTIFY_CMD=                            # called as: $NOTIFY_CMD "<one-line message>" for things the owner must see (optional)

# verification of the rebased commit before the integration branch moves
VERIFY_MODE=local                      # local = this machine runs the critical tests; remote = a verifier machine does (see 10-multi-machine.md)
VERIFY_TIMEOUT_MIN=120

# machine protection
HEAVY_LOCK=/tmp/software-factory-heavy.lock   # machine-wide: one heavy job (gate, E2E) at a time
MAX_FIX_RUNS=2                         # fix runs allowed at once while other work is held back (release first)
PARK_AFTER_MIN=180                     # a story in its fix loop this long is parked so it cannot block the queue
HEAVY_LIMIT_MIN=150                    # kill a heavy job (gate, critical E2E) held this long
HEAVY_TARGETED_LIMIT_MIN=45            # kill a targeted E2E held this long (it takes minutes; longer means it loops)
HEAVY_WARN_MIN=90
RELEASE_STALL_MIN=180                  # no release this long while stories wait => self-heal and notify
REDELIVER_MAX=3                        # automatic re-deliveries per story and window
REDELIVER_WINDOW_MIN=120
DISK_PATH=/                            # path whose free space is watched
DISK_LOW_GB=40                         # janitor cleans below this
DISK_CRITICAL_GB=10
INFRA_RETRY_MAX=24                     # retries (not counted as failures) for network/API/usage-limit errors per run
INFRA_RETRY_SLEEP=300                  # seconds between those retries
DAILY_BUDGET_USD=0                     # 0 = no cap; otherwise lanes pause when the day's agent cost passes it
STACK_MEM_GB=4                         # rough memory of one full stack; used by `factory doctor` to size parallelism
STACK_ENGINE=none                      # none | docker  (docker enables container throttling and leftover-stack cleanup)
STACK_NAME_PREFIX=                     # prefix of stacks to manage (docker project names); default fac-<PROJECT_NAME>
VERIFY_STACK_PREFIX=                   # prefix of verification stacks (default: <STACK_NAME_PREFIX>-verify)
PROTECT_PATHS_NOTE=                    # free text shown to agents about files they must not touch (see templates/prompts)

if [ -f "$FACTORY_CONF" ]; then
  # shellcheck disable=SC1090
  . "$FACTORY_CONF"
else
  [ "${FACTORY_ALLOW_NO_CONF:-}" = 1 ] || { echo "factory: no configuration at $FACTORY_CONF (run: factory init <repo>)" >&2; exit 2; }
fi

[ -n "$REPO" ] || { [ "${FACTORY_ALLOW_NO_CONF:-}" = 1 ] || { echo "factory: REPO is not set in $FACTORY_CONF" >&2; exit 2; }; }
[ -z "$WORKTREES" ] && [ -n "$REPO" ] && WORKTREES="$(dirname "$REPO")/$(basename "$REPO")-wt"
[ -n "$STATE_DIR" ] || STATE_DIR="$FACTORY_DIR/state"
[ -n "$STACK_NAME_PREFIX" ] || STACK_NAME_PREFIX="fac-$PROJECT_NAME"
[ -n "$VERIFY_STACK_PREFIX" ] || VERIFY_STACK_PREFIX="${STACK_NAME_PREFIX}-verify"
LOG="$STATE_DIR/progress.log"
SUPLOG="$STATE_DIR/supervisor.log"
RUNS="$STATE_DIR/runs"
PIDS="$STATE_DIR/pids"
mkdir -p "$STATE_DIR" "$RUNS" "$PIDS" 2>/dev/null || true

# ---------------------------------------------------------------- time, logs
ts()  { date '+%Y-%m-%d %H:%M'; }
now() { date +%s; }
# progress.log is the single human-readable event stream:  <ID> <EVENT> <text> <YYYY-MM-DD HH:MM>
log_event() { printf '%s %s %s\n' "$1" "$2" "${3:-} $(ts)" >> "$LOG"; }
say() { printf '%s %s\n' "$(ts)" "$*" >> "$SUPLOG"; }
notify() {  # notify "<message>": best effort, never fatal, rate-limited per message text
  local msg=$1 key
  [ -n "$NOTIFY_CMD" ] || return 0
  key=$(printf '%s' "$msg" | cksum | cut -d' ' -f1)
  if [ -f "$STATE_DIR/.notified.$key" ] && [ -n "$(find "$STATE_DIR/.notified.$key" -mmin -60 2>/dev/null)" ]; then return 0; fi
  : > "$STATE_DIR/.notified.$key"
  $NOTIFY_CMD "$msg" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------- portable system helpers
OS=$(uname -s)
file_mtime() { if [ "$OS" = Darwin ]; then stat -f %m "$1" 2>/dev/null; else stat -c %Y "$1" 2>/dev/null; fi; }
file_age_min() { local m; m=$(file_mtime "$1") || return 1; echo $(( ($(now) - m) / 60 )); }
free_gb() { df -Pk "${1:-$DISK_PATH}" 2>/dev/null | awk 'NR==2{print int($4/1048576)}'; }
mem_free_gb() {
  if [ "$OS" = Darwin ]; then
    vm_stat 2>/dev/null | awk '/page size of/{ps=$8} /Pages free/{f=$3} /Pages inactive/{i=$3} /Pages speculative/{s=$3} END{printf "%d", (f+i+s)*ps/1073741824}'
  else
    awk '/MemAvailable/{printf "%d", $2/1048576}' /proc/meminfo 2>/dev/null
  fi
}
cpu_count() { getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4; }
mem_total_gb() {
  if [ "$OS" = Darwin ]; then echo $(( $(sysctl -n hw.memsize) / 1073741824 )); else awk '/MemTotal/{printf "%d", $2/1048576}' /proc/meminfo; fi
}
etime_min() {  # etime_min <pid>: elapsed minutes of a process (ps etime is [[dd-]hh:]mm:ss on both systems)
  local e; e=$(ps -o etime= -p "$1" 2>/dev/null | tr -d ' ') || return 1
  [ -n "$e" ] || return 1
  printf '%s' "$e" | awk -F'[-:]' '{ n=NF; if (n==2) m=$1; else if (n==3) m=$1*60+$2; else m=$1*1440+$2*60+$3; print int(m) }'
}
pid_alive() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }
children() { pgrep -P "$1" 2>/dev/null || true; }
descendants() {  # descendants <pid>: all children, grandchildren, ...
  local c
  for c in $(children "$1"); do echo "$c"; descendants "$c"; done
}
kill_tree()   { local p; for p in $(descendants "$1") "$1"; do kill "-${2:-TERM}" "$p" 2>/dev/null || true; done; }
pause_tree()  { kill_tree "$1" STOP; }
resume_tree() { kill_tree "$1" CONT; }
proc_state() { ps -o stat= -p "$1" 2>/dev/null | cut -c1; }   # T = stopped
sedi() { if [ "$OS" = Darwin ]; then sed -i '' "$@"; else sed -i "$@"; fi; }

# ---------------------------------------------------------------- pid registry (never match processes by name)
# Every agent run, lane driver and delivery registers a pid file; the supervisor and quiet.sh only trust these files.
pid_file() { echo "$PIDS/$1.$2"; }         # pid_file <kind> <name>   kinds: build fix lane deliver verify
pid_register() { echo "$$" > "$(pid_file "$1" "$2")"; }
pid_unregister() { rm -f "$(pid_file "$1" "$2")"; }
pid_of() { local f; f=$(pid_file "$1" "$2"); [ -f "$f" ] && cat "$f"; }
pid_running() { local p; p=$(pid_of "$1" "$2"); pid_alive "$p"; }
list_runs() {  # list_runs <kind>: "<name> <pid>" of every live registered process of that kind (stale files removed)
  local f p n
  for f in "$PIDS"/"$1".*; do
    [ -e "$f" ] || continue
    p=$(cat "$f" 2>/dev/null); n=${f##*/}; n=${n#"$1".}
    if pid_alive "$p"; then echo "$n $p"; else rm -f "$f"; fi
  done
}

# ---------------------------------------------------------------- git and worktrees
git_main() { git -C "$REPO" "$@"; }
story_branch() { echo "${STORY_BRANCH_PREFIX}$1"; }
story_wt() { echo "$WORKTREES/$1"; }
sha_of() { git -C "$1" rev-parse HEAD; }

# ---------------------------------------------------------------- locks (mkdir is atomic on every filesystem)
# lock_take <dir> [wait-seconds]: waits, takes over a lock whose owner died or that was created and never filled.
lock_take() {
  local d=$1 max=${2:-0} waited=0 holder
  while ! mkdir "$d" 2>/dev/null; do
    holder=$(cat "$d/pid" 2>/dev/null || true)
    if [ -n "$holder" ] && ! pid_alive "$holder"; then rm -rf "$d"; continue; fi
    if [ -z "$holder" ] && [ -d "$d" ] && [ -z "$(find "$d" -mmin -1 2>/dev/null)" ]; then rm -rf "$d"; continue; fi
    [ "$max" -gt 0 ] && [ "$waited" -ge "$max" ] && return 1
    sleep 5; waited=$((waited + 5))
  done
  echo "$$" > "$d/pid"
  return 0
}
lock_release() { rm -rf "$1"; }
DELIVER_LOCK="$STATE_DIR/deliver.lock"   # serialises every write to the main checkout (deliveries AND manual fixes)

# ---------------------------------------------------------------- agent run result protocol
# An agent run ends with one line:  RESULT: DONE <short sha>   |   RESULT: BLOCKED <reason>
# parse-result.py turns the run's output into:  <STATUS> | turns=N tokens=N out=N cost=$X
parse_result() { python3 -I "$FACTORY_BIN/parse-result.py" "$1"; }

# ---------------------------------------------------------------- stacks (docker engine only)
docker_ok() { timeout 20 docker info >/dev/null 2>&1; }
# stop_containers <name-prefix>: one by one; a bulk stop can fail on some engines
stop_containers() {
  local c
  [ "$STACK_ENGINE" = docker ] || return 0
  for c in $(docker ps -q --filter "name=$1" 2>/dev/null); do docker stop -t 2 "$c" >/dev/null 2>&1 || true; done
}

# ---------------------------------------------------------------- stack contract
# Every CMD_* command that touches a stack runs with these variables, so a project's commands can name and port
# their stack without guessing, and two stacks never collide:
#   FACTORY_STORY      story id (or "verify-<n>" for a verification slot)
#   FACTORY_WORKTREE   the checkout the command runs in
#   FACTORY_COMMIT     the commit under test (verification only)
#   FACTORY_STACK_NAME unique, lowercase, safe as a docker compose project name: <prefix>-<story>
#   FACTORY_PORT_BASE  first of 20 consecutive ports reserved for this stack (20000 + 20 * hash(name) % 1000)
export_stack_env() {  # export_stack_env <story> <worktree> [commit] [stack-prefix]
  local story=$1 wt=$2 commit=${3:-} prefix=${4:-$STACK_NAME_PREFIX} h
  FACTORY_STORY=$story; FACTORY_WORKTREE=$wt; FACTORY_COMMIT=$commit
  FACTORY_STACK_NAME=$(printf '%s-%s' "$prefix" "$story" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9\n-' '-' | cut -c1-48)
  h=$(printf '%s' "$FACTORY_STACK_NAME" | cksum | cut -d' ' -f1)
  FACTORY_PORT_BASE=$((20000 + (h % 1000) * 20))
  export FACTORY_STORY FACTORY_WORKTREE FACTORY_COMMIT FACTORY_STACK_NAME FACTORY_PORT_BASE
}
# run_cmd <command-string> [cwd]: run a configured command through sh with the stack contract in its environment.
run_cmd() {
  local c=$1 d=${2:-$PWD}
  [ -n "$c" ] || return 0
  (cd "$d" && sh -c "$c")
}

# ---------------------------------------------------------------- story state, read from progress.log
last_event() {  # last_event <story>: the last event word logged for the story, or empty
  grep -E "^$1 [A-Z][A-Z-]+" "$LOG" 2>/dev/null | tail -1 | awk '{print $2}'
}
story_done()     { grep -qE "^$1 (DONE|RELEASED)( |$)" "$LOG" 2>/dev/null; }
story_released() { grep -qE "^$1 RELEASED( |$)" "$LOG" 2>/dev/null; }
story_parked()   { [ -f "$STATE_DIR/.parked.$1" ]; }
story_exists() {
  if [ -n "$CMD_STORY_EXISTS" ]; then FACTORY_STORY=$1 run_cmd "$CMD_STORY_EXISTS" "$REPO"; return $?; fi
  [ -n "$PLAN_DIR" ] || return 0
  case "$1" in   # SWEEP-<EPIC>-<n>: a batch of the not-yet-built stories of an epic
    SWEEP-*-*) local e=${1#SWEEP-}; e=${e%-*}; grep -rqE "^#{1,4} +$e-" "$PLAN_DIR" 2>/dev/null; return $? ;;
  esac
  grep -rqE "^#{1,4} +$1([^A-Za-z0-9-]|$)" "$PLAN_DIR" 2>/dev/null
}

# ---------------------------------------------------------------- spend
spend_today() {  # agent cost in USD of today's DONE/RELEASED lines (the parse line carries cost=$X)
  local d; d=$(date '+%Y-%m-%d')
  grep -E " cost=\\$" "$LOG" 2>/dev/null | grep -F "$d" | sed -n 's/.*cost=\$\([0-9.]*\).*/\1/p' | awk '{s+=$1} END{printf "%.2f", s}'
}
budget_ok() {
  [ "${DAILY_BUDGET_USD:-0}" = 0 ] && return 0
  awk -v s="$(spend_today)" -v b="$DAILY_BUDGET_USD" 'BEGIN{exit !(s < b)}'
}
