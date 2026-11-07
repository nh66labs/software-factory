#!/usr/bin/env bash
# critical-e2e.sh <commit>: the end-to-end gate of a release, on exactly one commit.
#
#   - a fresh verification worktree, detached at the commit (never the main checkout: its stack may be the live demo)
#   - a fresh stack name per run and a fresh database (CMD_STACK_RESET); the stack is stopped when the run ends
#   - the critical tests (CMD_E2E_CRITICAL) with NO retries; the verdict file is the only evidence, the exit code alone
#     is not trusted: ok=true, passed>=1 (zero tests selected is a failure), failed=0, retries=0, commit matches
#
# Exit: 0 every critical test passed; 1 a test failed / was retried into a pass / was skipped / none ran;
#       2 the run could not complete (stack did not start, no verdict). It never moves a branch or pushes.
# The verdict is also copied to state/verdicts/<sha>.json (the reasons are what a fix run reads).
. "$(dirname "$0")/lib/common.sh"
SHA=$(git_main rev-parse --verify "${1:?usage: critical-e2e.sh <commit>}^{commit}") || exit 2
mkdir -p "$STATE_DIR/verdicts" "$WORKTREES"
[ -n "$CMD_E2E_CRITICAL" ] && [ -n "$CMD_STACK_RESET" -o "$STACK_ENGINE" = none ] || { echo "critical-e2e: CMD_E2E_CRITICAL (and CMD_STACK_RESET) must be configured" >&2; exit 2; }

# Docker can leave a ghost endpoint that blocks removing a stack's network ("has active endpoints"); that stack name
# then never starts again, and removing it fails silently. So every run takes a NEW slot, skipping slots whose network
# is stuck, and a finished stack is always stopped (leftover stacks exhaust the VM's memory and the browsers crash).
slot_blocked() {
  [ "$STACK_ENGINE" = docker ] || return 1
  local net="${VERIFY_STACK_PREFIX}-verify-$1_default"
  docker network inspect "$net" >/dev/null 2>&1 && ! docker network rm "$net" >/dev/null 2>&1
}
n=1
while [ $n -le 200 ]; do slot_blocked "$n" || break; n=$((n + 1)); done
SLOT="verify-$n"
WT="$WORKTREES/$SLOT"
if [ -d "$WT" ]; then (cd "$WT" && git switch --detach --quiet "$SHA") || exit 2; else git_main worktree add --detach "$WT" "$SHA" >/dev/null || exit 2; fi
[ "$(sha_of "$WT")" = "$SHA" ] || { echo "critical-e2e: $WT is not at $SHA" >&2; exit 2; }
[ -z "$(git -C "$WT" status --porcelain --untracked-files=no)" ] || { echo "critical-e2e: $WT has uncommitted changes" >&2; exit 2; }
export_stack_env "$SLOT" "$WT" "$SHA" "$VERIFY_STACK_PREFIX"
echo "critical-e2e: $SHA in $WT (stack $FACTORY_STACK_NAME)"
teardown() { stop_containers "$FACTORY_STACK_NAME"; [ -n "$CMD_STACK_DOWN" ] && run_cmd "$CMD_STACK_DOWN" "$WT" >/dev/null 2>&1; stop_containers "$VERIFY_STACK_PREFIX"; }
stop_containers "$VERIFY_STACK_PREFIX"     # leftovers of earlier runs
trap teardown EXIT

if [ -n "$CMD_STACK_RESET" ] && ! run_cmd "$CMD_STACK_RESET" "$WT"; then echo "critical-e2e: the stack did not start" >&2; exit 2; fi
VERDICT="$WT/$E2E_VERDICT_FILE"
rm -f "$VERDICT"
CODE=0
(cd "$WT" && FACTORY_COMMIT=$SHA sh -c "$CMD_E2E_CRITICAL" factory-critical "$SHA") || CODE=$?   # the commit is $1 (and $FACTORY_COMMIT)
[ -f "$VERDICT" ] || { echo "critical-e2e: the run left no verdict ($VERDICT)" >&2; exit 2; }
cp "$VERDICT" "$STATE_DIR/verdicts/$SHA.json" 2>/dev/null || true
python3 -I "$FACTORY_BIN/verdict-check.py" "$VERDICT" "$SHA" "$CODE"
