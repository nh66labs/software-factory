#!/usr/bin/env bash
# deliver.sh <story>: deliver a finished story branch.
#   1. rebase the story on the integration branch (a conflict returns exit 1: a fix run resolves it in the worktree)
#   2. record the critical-test pass on the REBASED commit, before anything moves (exit 5 on failure: a fix run)
#   3. fast-forward the integration branch in the main checkout, push it (PUSH-PENDING if refused: retried later)
#   4. release to production (AUTO_RELEASE=1), refresh the demo, remove the worktree, stack and branch
# Exit: 0 delivered; 1 rebase/merge conflict; 5 critical tests failed on the rebased result; 4 other.
#
# Rules that each exist because of a failure (references/08-failure-catalog.md):
#  - Nothing reaches the integration branch that has not passed the critical tests on that exact commit; the first full
#    run on merged code must never be the release.
#  - One delivery at a time, and the same lock guards every manual write to the main checkout.
#  - Story runs are paused once this delivery holds the heavy lock and stay paused until the delivery ends (one resume,
#    in the EXIT trap): a build resumed in between starts its own gate and the delivery waits a whole gate for the machine.
. "$(dirname "$0")/lib/common.sh"
story=${1:?usage: deliver.sh <story>}
wt=$(story_wt "$story"); out="$RUNS/$story.merge"; br=$(story_branch "$story")
[ -d "$wt" ] || { echo "deliver: no worktree for $story" >&2; exit 4; }
lock_take "$DELIVER_LOCK" || exit 4
pid_register deliver "$story"
cleanup() { "$FACTORY_BIN/quiet.sh" resume; pid_unregister deliver "$story"; lock_release "$DELIVER_LOCK"; }
trap cleanup EXIT
export FACTORY_HEAVY_PRIORITY=1     # this delivery's tests, push gate and release go before story runs' gates

cd "$REPO" || exit 4
[ "$(git branch --show-current)" = "$INTEGRATION_BRANCH" ] || git switch -q "$INTEGRATION_BRANCH" || exit 4
git fetch -q "$REMOTE" 2>/dev/null || true
if git rev-parse -q --verify "refs/remotes/$REMOTE/$INTEGRATION_BRANCH" >/dev/null && git merge-base --is-ancestor "$INTEGRATION_BRANCH" "refs/remotes/$REMOTE/$INTEGRATION_BRANCH" && [ "$(git rev-parse "$INTEGRATION_BRANCH")" != "$(git rev-parse "refs/remotes/$REMOTE/$INTEGRATION_BRANCH")" ]; then
  git merge -q --ff-only "refs/remotes/$REMOTE/$INTEGRATION_BRANCH" >/dev/null 2>&1 || true    # another machine delivered first
fi
(cd "$wt" && git rebase "$INTEGRATION_BRANCH" > "$out" 2>&1) || exit 1
sha=$(sha_of "$wt")

if [ "$VERIFY_MODE" = remote ]; then
  CODE=0; "$FACTORY_BIN/record-critical.sh" "$sha" >> "$out" 2>&1 || CODE=$?
else
  CODE=0
  "$FACTORY_BIN/heavy" sh -c "\"$FACTORY_BIN/quiet.sh\" pause; \"$FACTORY_BIN/record-critical.sh\" $sha" >> "$out" 2>&1 || CODE=$?
fi
if [ "$CODE" -ne 0 ]; then
  log_event "$story" CRITICAL-E2E-FAILED "on the rebased result (see runs/$story.merge)"
  exit 5
fi
git merge --ff-only "$br" >> "$out" 2>&1 || exit 1
if ! git push "$REMOTE" "$INTEGRATION_BRANCH" >> "$out" 2>&1; then
  log_event "$story" PUSH-PENDING "(merged locally; see runs/$story.merge)"
fi
if [ "$AUTO_RELEASE" = 1 ]; then
  if "$FACTORY_BIN/release.sh" >> "$out" 2>&1; then
    log_event "$story" RELEASED "$(git rev-parse --short HEAD) to production"
    notify "Released $story ($(git rev-parse --short HEAD))"
  else
    log_event "$story" RELEASE-FAILED "(delivered to $INTEGRATION_BRANCH; see runs/$story.merge)"
    notify "Release of $story failed; it is on $INTEGRATION_BRANCH"
  fi
fi
[ -n "$CMD_DEMO_REFRESH" ] && { run_cmd "$CMD_DEMO_REFRESH" "$REPO" >> "$out" 2>&1 || echo "deliver: demo refresh failed (non-fatal)" >> "$out"; }
export_stack_env "$story" "$wt"
[ -n "$CMD_STACK_DOWN" ] && run_cmd "$CMD_STACK_DOWN" "$wt" >/dev/null 2>&1
git worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"
git worktree prune
git branch -d "$br" >/dev/null 2>&1 || true
exit 0
