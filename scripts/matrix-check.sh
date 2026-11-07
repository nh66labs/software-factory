#!/usr/bin/env bash
# matrix-check.sh   The FULL matrix (every browser/device project, every language, visual baselines) on a clean worktree of the
# integration branch. Stories and deliveries run only the critical set to save time and tokens; this is where the rest is
# checked. Run it on a schedule (cron/systemd timer/the coordinator's loop, e.g. every few hours when the machine is quiet).
# It takes the heavy lock, so it waits behind deliveries and never beside them. A failure is logged and alerted; it is fix
# work (a story or a ticket), not a gate on the next release. Result lines: state/matrix.log.
. "$(dirname "$0")/lib/common.sh"
[ -n "$CMD_E2E_MATRIX" ] || { echo "matrix-check: CMD_E2E_MATRIX is not set" >&2; exit 2; }
SHA=$(git_main rev-parse "$INTEGRATION_BRANCH") || exit 2
WT="$WORKTREES/matrix-check"
if [ -d "$WT" ]; then export_stack_env matrix-check "$WT"; [ -n "$CMD_STACK_DOWN" ] && run_cmd "$CMD_STACK_DOWN" "$WT" >/dev/null 2>&1; git_main worktree remove --force "$WT" >/dev/null 2>&1 || rm -rf "$WT"; fi
git_main worktree add -q --detach "$WT" "$SHA" || exit 2
export_stack_env matrix-check "$WT" "$SHA"
CODE=0
"$FACTORY_BIN/heavy" sh -c "cd '$WT' && { [ -z '$CMD_STACK_RESET' ] || ($CMD_STACK_RESET); } && ($CMD_E2E_MATRIX)" > "$STATE_DIR/matrix.out" 2>&1 || CODE=$?
echo "$(ts) matrix-check $INTEGRATION_BRANCH ${SHA:0:7} exit=$CODE $(tail -n 5 "$STATE_DIR/matrix.out" | tr '\n' ' ' | cut -c1-200)" >> "$STATE_DIR/matrix.log"
[ -n "$CMD_STACK_DOWN" ] && run_cmd "$CMD_STACK_DOWN" "$WT" >/dev/null 2>&1
git_main worktree remove --force "$WT" >/dev/null 2>&1 || rm -rf "$WT"
if [ $CODE -ne 0 ]; then log_event lane MATRIX-FAILED "${SHA:0:7} (see state/matrix.out)"; notify "Full matrix failed on ${SHA:0:7}"; fi
exit $CODE
