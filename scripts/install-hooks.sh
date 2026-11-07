#!/usr/bin/env bash
# install-hooks.sh <repo>   Installs the factory git hooks into the repository's SHARED git directory (outside every
# working tree) and records the settings the hooks read. Run it once per clone, by the human operator: agents must never be
# able to edit the guards they run under, so their settings deny editing .git and this script.
FACTORY_ALLOW_NO_CONF=1 . "$(dirname "$0")/lib/common.sh"
repo=${1:-$REPO}; [ -n "$repo" ] || { echo "usage: install-hooks.sh <repo>" >&2; exit 2; }
common=$(cd -P "$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)" && pwd -P)
hooks="$common/hooks"; mkdir -p "$hooks"
for h in reference-transaction pre-push; do cp "$FACTORY_BIN/githooks/$h" "$hooks/$h.new" && chmod 755 "$hooks/$h.new" && mv -f "$hooks/$h.new" "$hooks/$h"; done
git -C "$repo" config core.hooksPath "$hooks"
git -C "$repo" config factory.productionBranch "$PRODUCTION_BRANCH"
[ -n "$CMD_GATE_FAST" ] && git -C "$repo" config factory.gateFast "$CMD_GATE_FAST"
git -C "$repo" config factory.heavy "$FACTORY_BIN/heavy"
echo "factory hooks installed in $hooks (production branch: $PRODUCTION_BRANCH)"
