#!/usr/bin/env bash
# verifier-daemon.sh: runs on a dedicated verification machine (VERIFY_MODE=remote on the builders). Polls the remote for
# candidate commits (refs/factory/candidates/*), runs the critical tests on each exactly once, and answers through the
# remote: tag e2e-critical/<sha> on a pass, annotated tag refs/factory/rejected/<sha> (message = the reasons) on a failure.
# The builders never need to reach this machine; the git remote is the only bus.
. "$(dirname "$0")/lib/common.sh"
pid_register lane verifier
cd "$REPO" || exit 2
while :; do
  git fetch -q "$REMOTE" '+refs/factory/candidates/*:refs/factory/candidates/*' '+refs/tags/e2e-critical/*:refs/tags/e2e-critical/*' 2>/dev/null
  for ref in $(git for-each-ref --format='%(refname)' refs/factory/candidates); do
    sha=${ref##*/}
    git rev-parse -q --verify "refs/tags/e2e-critical/$sha" >/dev/null && { git update-ref -d "$ref"; continue; }
    git ls-remote --exit-code "$REMOTE" "refs/factory/rejected/$sha" >/dev/null 2>&1 && { git update-ref -d "$ref"; continue; }
    echo "$(ts) verifying $sha" >> "$STATE_DIR/verifier.log"
    out="$RUNS/verify-$sha.log"
    if FACTORY_HEAVY_PRIORITY=1 VERIFY_MODE=local "$FACTORY_BIN/record-critical.sh" "$sha" > "$out" 2>&1; then
      echo "$(ts) PASS $sha" >> "$STATE_DIR/verifier.log"
    else
      msg="critical tests failed on $sha at $(ts)
$(tail -n 60 "$out")"
      git tag -a -f "factory-rejected-$sha" -m "$msg" "$sha" 2>/dev/null
      git push -q "$REMOTE" "+refs/tags/factory-rejected-$sha:refs/factory/rejected/$sha" 2>/dev/null
      git tag -d "factory-rejected-$sha" >/dev/null 2>&1
      echo "$(ts) FAIL $sha" >> "$STATE_DIR/verifier.log"
    fi
    git update-ref -d "$ref"
  done
  sleep 30
done
