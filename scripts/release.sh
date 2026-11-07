#!/usr/bin/env bash
# release.sh [--check-only]: release the integration branch to production.
# Fast-forwards PRODUCTION_BRANCH to INTEGRATION_BRANCH in the main checkout and pushes it (the push is what deploys).
# It refuses unless the critical tests passed on this exact commit (record-critical.sh: not repeated when the delivery
# already recorded it). After the push it runs CMD_POST_RELEASE_CHECK (a smoke test of the deployed system) and logs the
# result, because a green deploy workflow only proves that the deploy script ran.
#   --check-only   run/verify the critical tests, change nothing
# Exit: 0 released (or nothing to release); otherwise the failing step's code.
. "$(dirname "$0")/lib/common.sh"
cd "$REPO" || exit 2
CHECK_ONLY=0
case "${1:-}" in --check-only) CHECK_ONLY=1 ;; "") ;; *) echo "release: unknown argument $1" >&2; exit 2 ;; esac
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "release: uncommitted changes in the main checkout" >&2; exit 2; }
[ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ] || { echo "release: run it in the main checkout" >&2; exit 2; }
git fetch -q "$REMOTE" 2>/dev/null || true
if [ "$PRODUCTION_BRANCH" = "$INTEGRATION_BRANCH" ]; then echo "release: single environment, nothing to merge"; exit 0; fi
git merge-base --is-ancestor "$PRODUCTION_BRANCH" "$INTEGRATION_BRANCH" || { echo "release: $PRODUCTION_BRANCH is not an ancestor of $INTEGRATION_BRANCH" >&2; exit 2; }
SHA=$(git rev-parse "$INTEGRATION_BRANCH")
[ "$SHA" = "$(git rev-parse "$PRODUCTION_BRANCH")" ] && { echo "release: production is already at $SHA"; exit 0; }
CODE=0
if [ "$CHECK_ONLY" = 1 ]; then
  "$FACTORY_BIN/heavy" "$FACTORY_BIN/critical-e2e.sh" "$SHA" || CODE=$?
  [ "$CODE" -eq 0 ] && echo "release: --check-only: the critical tests passed on $SHA; nothing recorded or released"
  exit "$CODE"
fi
"$FACTORY_BIN/record-critical.sh" "$SHA" || CODE=$?
if [ "$CODE" -ne 0 ]; then echo "release: NOT released. The critical tests did not pass (exit $CODE); nothing was merged or pushed." >&2; exit "$CODE"; fi
[ "$(git rev-parse "$INTEGRATION_BRANCH")" = "$SHA" ] || { echo "release: $INTEGRATION_BRANCH moved during the test run; run it again" >&2; exit 2; }
START_BRANCH=$(git branch --show-current)
git switch -q "$PRODUCTION_BRANCH" || exit 2
trap 'git switch -q "$START_BRANCH"' EXIT
FACTORY_ALLOW_PRODUCTION_UPDATE=1 git merge --ff-only "$INTEGRATION_BRANCH" || exit 2
git push "$REMOTE" "$PRODUCTION_BRANCH" || { echo "release: push of $PRODUCTION_BRANCH refused" >&2; exit 2; }
echo "Released $(git log -1 --format='%h %s')"
if [ -n "$CMD_POST_RELEASE_CHECK" ]; then
  ok=0
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18; do   # the deploy takes minutes: poll up to ~18 min
    if run_cmd "$CMD_POST_RELEASE_CHECK" "$REPO" >/dev/null 2>&1; then ok=1; break; fi
    sleep 60
  done
  if [ $ok = 1 ]; then echo "release: post-release check passed"; else echo "release: POST-RELEASE CHECK FAILED for $SHA" >&2; log_event release POST-RELEASE-CHECK-FAILED "$SHA"; notify "Release $SHA deployed but the post-release check failed"; exit 3; fi
fi
