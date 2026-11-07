#!/usr/bin/env bash
# record-critical.sh <commit>: make sure the critical tests passed on this exact commit, and record the pass as the
# annotated tag `e2e-critical/<sha>` pushed to the remote. A commit that already has the tag is never tested again.
#
# The delivery of every story calls it on the REBASED result before the integration branch moves, so the integration
# branch is releasable at every commit and the release step only merges. The deploy guard (templates/ci) refuses to
# deploy a production commit without this tag, so a push by any other route does not deploy.
#
#   VERIFY_MODE=local   this machine runs the tests (one heavy job at a time)
#   VERIFY_MODE=remote  the commit is offered to a verifier machine as refs/factory/candidates/<sha> and this script waits
#                       for its answer: the tag (pass) or refs/factory/rejected/<sha> (an annotated tag whose message holds
#                       the reasons). See references/10-multi-machine.md.
# Exit: 0 recorded (now or before); 1 tests failed; 2 could not complete.
. "$(dirname "$0")/lib/common.sh"
SHA=$(git_main rev-parse --verify "${1:?usage: record-critical.sh <commit>}^{commit}") || exit 2
cd "$REPO" || exit 2
TAG="e2e-critical/$SHA"
have_tag() { git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; }
if have_tag; then echo "record-critical: $SHA already has its critical pass; not tested again"; exit 0; fi
if git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$TAG" >/dev/null 2>&1; then
  git fetch -q "$REMOTE" "+refs/tags/$TAG:refs/tags/$TAG" 2>/dev/null && { echo "record-critical: $SHA already has its critical pass on $REMOTE"; exit 0; }
fi

if [ "$VERIFY_MODE" = remote ]; then
  git push -q "$REMOTE" "$SHA:refs/factory/candidates/$SHA" || { echo "record-critical: cannot offer $SHA to the verifier" >&2; exit 2; }
  echo "record-critical: $SHA offered to the verifier; waiting up to $VERIFY_TIMEOUT_MIN min"
  end=$(( $(now) + VERIFY_TIMEOUT_MIN * 60 ))
  while [ "$(now)" -lt "$end" ]; do
    if git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$TAG" >/dev/null 2>&1; then
      git fetch -q "$REMOTE" "+refs/tags/$TAG:refs/tags/$TAG" 2>/dev/null; echo "record-critical: verifier passed $SHA"; exit 0
    fi
    if git ls-remote --exit-code "$REMOTE" "refs/factory/rejected/$SHA" >/dev/null 2>&1; then
      git fetch -q "$REMOTE" "+refs/factory/rejected/$SHA:refs/factory/rejected/$SHA" 2>/dev/null
      { echo "critical-e2e: FAILED on the verifier:"; git cat-file -p "refs/factory/rejected/$SHA" 2>/dev/null | sed 's/^/  /'; } >&2
      exit 1
    fi
    sleep 20
  done
  echo "record-critical: the verifier did not answer in $VERIFY_TIMEOUT_MIN min" >&2; exit 2
fi

CODE=0
"$FACTORY_BIN/heavy" "$FACTORY_BIN/critical-e2e.sh" "$SHA" || CODE=$?
[ "$CODE" -eq 0 ] || exit "$CODE"
VERDICT="$STATE_DIR/verdicts/$SHA.json"
PASSED=$(python3 -I -c "import json,sys;print(json.load(open(sys.argv[1])).get('passed',0))" "$VERDICT" 2>/dev/null || echo 0)
[ "${PASSED:-0}" -ge 1 ] || { echo "record-critical: the verdict shows no passed test" >&2; exit 1; }
git tag -a "$TAG" -m "critical-tests-passed: $PASSED
critical-tests-failed: 0
commit: $SHA
retries: 0
run: $(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SHA"
git push -q "$REMOTE" "refs/tags/$TAG" || echo "record-critical: tag recorded locally; push to $REMOTE failed (the release will retry)" >&2
echo "record-critical: $PASSED critical test run(s) passed on $SHA; recorded"
