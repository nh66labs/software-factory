#!/usr/bin/env bash
# PreToolUse hook (Claude Code): refuse edits to the guard rails and to already-merged migrations. Reads the tool call JSON
# on stdin; exit 2 blocks the call and shows the message to the agent. Install as .claude/hooks/protect-rails.sh (executable).
input=$(cat)
path=$(printf '%s' "$input" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print((d.get("tool_input") or {}).get("file_path") or (d.get("tool_input") or {}).get("notebook_path") or "")' 2>/dev/null)
[ -n "$path" ] || exit 0
case "$path" in
  */.git/*|*/.githooks/*|*/.claude/settings*|*/.claude/hooks/*|*/.github/workflows/*|*/.factory/bin/*|*/deploy/check-e2e-marker.sh)
    echo "blocked: $path is a guard rail owned by the human operator" >&2; exit 2 ;;
esac
# merged migrations are immutable: compare against the integration branch (adapt the directory name)
case "$path" in
  */migrations/*)
    rel=${path#*/migrations/}
    if git -C "$(dirname "$path")" cat-file -e "staging:migrations/$rel" 2>/dev/null; then
      echo "blocked: $rel is already merged; add a new migration instead" >&2; exit 2
    fi ;;
esac
exit 0
