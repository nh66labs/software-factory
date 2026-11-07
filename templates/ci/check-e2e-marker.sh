#!/usr/bin/env bash
# The deploy guard: the commit being deployed must carry the recorded pass of the critical end-to-end tests, the annotated
# tag `e2e-critical/<sha>` that record-critical.sh pushed before the production branch moved. A push of the production branch
# by any other route (a hand merge, a fast-forward from a clone) has no tag and does not deploy.
#
#   check-e2e-marker.sh <sha> [<reason>]
# With a <reason> (the workflow's manual `allow_unverified` input) a missing marker is allowed and the reason is printed into
# the log: an owner decision, visible in the run. Exit 0 verified or allowed; 1 not verified.
# A process guard, not a security boundary: whoever can push can push a tag. It stops the mistake of deploying a commit nobody
# tested, which is the failure it exists for.
set -euo pipefail
SHA=${1:?usage: check-e2e-marker.sh <sha> [<reason>]}
REASON=${2:-}
REMOTE=${E2E_MARKER_REMOTE:-origin}
TAG="e2e-critical/$SHA"
refuse() {
  if [ -n "$REASON" ]; then
    echo "deploy guard: NO verified critical E2E for $SHA ($1) -- allowed by the owner: $REASON" >&2
    exit 0
  fi
  echo "deploy guard: REFUSED. $1" >&2
  echo "Release with release.sh (it runs the critical tests and records the pass), or start this workflow by hand with allow_unverified set to a reason." >&2
  exit 1
}
if ! git fetch --no-tags -q "$REMOTE" "+refs/tags/$TAG:refs/tags/$TAG" 2>/dev/null; then
  refuse "no tag $TAG on $REMOTE: the critical E2E pass of this commit is not recorded"
fi
[ "$(git cat-file -t "refs/tags/$TAG")" = "tag" ] || refuse "$TAG is not an annotated tag"
[ "$(git rev-parse "refs/tags/$TAG^{commit}")" = "$SHA" ] || refuse "$TAG points at another commit"
BODY=$(git tag -l --format='%(contents)' "$TAG")
PASSED=$(printf '%s\n' "$BODY" | sed -n 's/^critical-tests-passed: \([0-9][0-9]*\)$/\1/p' | head -n 1)
FAILED=$(printf '%s\n' "$BODY" | sed -n 's/^critical-tests-failed: \([0-9][0-9]*\)$/\1/p' | head -n 1)
[ -n "$PASSED" ] && [ "$PASSED" -ge 1 ] || refuse "$TAG records no passed critical test"
[ "$FAILED" = "0" ] || refuse "$TAG records failed critical tests"
echo "deploy guard: $SHA passed $PASSED critical E2E run(s), recorded in $TAG"
