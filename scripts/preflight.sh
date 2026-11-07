#!/usr/bin/env bash
# preflight.sh   `factory doctor`: checks the machine and the configuration BEFORE the first run and sizes the parallelism.
# Every check that failed in production at least once is here. Exit 0 = ready; 1 = fix the FAIL lines first.
FACTORY_ALLOW_NO_CONF=1 . "$(dirname "$0")/lib/common.sh"
bad=0
ok()   { echo "OK    $*"; }
warn() { echo "WARN  $*"; }
fail() { echo "FAIL  $*"; bad=1; }
for t in git python3 sed awk pgrep; do command -v $t >/dev/null 2>&1 && ok "$t found" || fail "$t is missing"; done
[ -f "$FACTORY_CONF" ] && ok "configuration $FACTORY_CONF" || { fail "no factory.conf (run: factory init <repo>)"; exit 1; }
[ -d "$REPO/.git" ] || [ -f "$REPO/.git" ] && ok "repository $REPO" || fail "REPO is not a git repository"
git -C "$REPO" rev-parse -q --verify "$INTEGRATION_BRANCH" >/dev/null 2>&1 && ok "integration branch $INTEGRATION_BRANCH exists" || fail "integration branch $INTEGRATION_BRANCH does not exist (create it from the production branch)"
git -C "$REPO" rev-parse -q --verify "$PRODUCTION_BRANCH" >/dev/null 2>&1 && ok "production branch $PRODUCTION_BRANCH exists" || fail "production branch $PRODUCTION_BRANCH does not exist"
git -C "$REPO" remote get-url "$REMOTE" >/dev/null 2>&1 && ok "remote $REMOTE configured" || warn "no remote $REMOTE: nothing is pushed, nothing deploys"
if git -C "$REPO" remote get-url "$REMOTE" >/dev/null 2>&1; then
  timeout 30 git -C "$REPO" ls-remote -q "$REMOTE" >/dev/null 2>&1 && ok "remote reachable" || fail "remote $REMOTE is not reachable (credentials? network?)"
fi
hp=$(git -C "$REPO" config core.hooksPath 2>/dev/null); [ -n "$hp" ] && ok "git hooks installed ($hp)" || warn "git hooks are not installed (scripts/install-hooks.sh): the production branch is unprotected"
for c in CMD_GATE_FAST CMD_GATE_FULL CMD_E2E_CRITICAL E2E_VERDICT_FILE; do [ -n "$(eval echo "\${$c}")" ] && ok "$c set" || fail "$c is not set (see references/11-adapting-to-stack.md)"; done
[ -n "$CMD_STACK_RESET" ] && ok "CMD_STACK_RESET set" || warn "CMD_STACK_RESET not set: the critical run cannot start a fresh stack"
[ -n "$CMD_POST_RELEASE_CHECK" ] || warn "no CMD_POST_RELEASE_CHECK: a release is not smoke-tested"
[ -n "$NOTIFY_CMD" ] || warn "no NOTIFY_CMD: nobody is told when something breaks while you are away"
[ -n "$PLAN_DIR" ] && [ -d "$PLAN_DIR" ] && ok "plan at $PLAN_DIR" || warn "PLAN_DIR not set or missing: unknown story ids will not be caught"
case "$AGENT_ADAPTER" in
  claude) command -v claude >/dev/null 2>&1 && ok "claude CLI found" || fail "claude CLI not found" ;;
  codex)  command -v codex  >/dev/null 2>&1 && ok "codex CLI found"  || fail "codex CLI not found" ;;
  generic) [ -n "${AGENT_CMD:-}" ] && ok "AGENT_CMD set" || fail "AGENT_CMD not set" ;;
esac
[ -n "$CMD_AGENT_AUTH_CHECK" ] && { run_cmd "$CMD_AGENT_AUTH_CHECK" "$REPO" >/dev/null 2>&1 && ok "agent logged in" || fail "agent CLI not logged in"; }
if [ "$STACK_ENGINE" = docker ]; then docker_ok && ok "docker responds" || fail "docker does not respond"; fi
# the network the agent needs: a night offline once turned finished stories into failures
for h in ${PING_HOSTS:-api.anthropic.com github.com}; do
  getent hosts "$h" >/dev/null 2>&1 || (command -v dscacheutil >/dev/null 2>&1 && dscacheutil -q host -a name "$h" 2>/dev/null | grep -q ip_address) \
    && ok "DNS resolves $h" || warn "DNS does not resolve $h"
done
f=$(free_gb); [ "${f:-0}" -ge "$DISK_LOW_GB" ] && ok "disk ${f} GB free" || warn "disk ${f} GB free (below DISK_LOW_GB=$DISK_LOW_GB)"
cpus=$(cpu_count); mem=$(mem_total_gb)
by_cpu=$((cpus / 3)); by_mem=$(( (mem - 2) / STACK_MEM_GB )); rec=$by_cpu; [ $by_mem -lt $rec ] && rec=$by_mem; [ $rec -lt 1 ] && rec=1
ok "capacity: ${cpus} cpus, ${mem} GB RAM, ~${STACK_MEM_GB} GB per full stack => at most $rec parallel story stacks (plus one verification stack)"
nl=$(ls "$FACTORY_DIR"/queues/*.txt 2>/dev/null | wc -l | tr -d ' '); [ "$nl" -gt "$rec" ] && warn "$nl lanes are configured but this machine sustains about $rec: expect timeouts that look like product bugs"
[ "$OS" = Darwin ] && { pmset -g assertions 2>/dev/null | grep -q caffeinate && ok "machine is kept awake" || warn "nothing keeps the machine awake (factory keepawake)"; }
[ -f "$HOME/.claude.json" ] && warn "headless runs ignore project permission settings in a directory whose trust dialog was never accepted: open the agent interactively once in $REPO and accept it"
exit $bad
