# Adapter for Claude Code (headless): `claude -p`. Defines agent_exec <prompt-file> <cwd> <out-json> <err-file> <effort>.
#
# LEAST PRIVILEGE BY DEFAULT. A headless run cannot answer a permission prompt, so it needs a pre-approved set of commands,
# and nothing more:
#   CLAUDE_PERMISSION_MODE   default acceptEdits (file edits allowed; every command must be on the allow list of the
#                            project's .claude/settings.json; deny rules and hooks apply). `bypassPermissions` is opt-in,
#                            only on a dedicated machine/VM with nothing to lose, and some hosts refuse to launch it.
#   AGENT_ALLOWED_TOOLS      optional extra --allowedTools list (space separated patterns), e.g. 'Bash(./run:*)'.
# Project settings (allow AND deny lists) are IGNORED in a directory whose trust dialog was never accepted ("Ignoring N
# permissions.allow entries ... workspace has not been trusted" in the run's stderr): accept it once, interactively, in the
# checkout runs start from. `factory agent-smoke` proves permissions, trust and the deny rules with one real run.
# A command on the "ask" list is a trap (the run cannot answer): the prompts name only allowed commands.
agent_exec() {
  local prompt=$1 cwd=$2 out=$3 err=$4 effort=$5
  local args
  args=(-p "$(cat "$prompt")" --output-format json --permission-mode "${CLAUDE_PERMISSION_MODE:-acceptEdits}")
  [ -n "$AGENT_MODEL" ] && args+=(--model "$AGENT_MODEL")
  [ -n "$effort" ] && args+=(--effort "$effort")
  [ -n "${AGENT_ALLOWED_TOOLS:-}" ] && args+=(--allowedTools $AGENT_ALLOWED_TOOLS)
  # The project's settings are passed EXPLICITLY, so allow/deny rules and hooks apply even where the trust dialog was never
  # accepted (a new project, a fresh machine). Without this a headless run in an untrusted folder has no allow list (it can do
  # nothing) and, worse, no deny list. Override with CLAUDE_SETTINGS_FILE.
  local settings=${CLAUDE_SETTINGS_FILE:-$REPO/.claude/settings.json}
  [ -f "$settings" ] && args+=(--settings "$settings")
  # Story worktrees live NEXT TO the repository; the agent may only edit inside its start folder plus added folders.
  [ -n "${WORKTREES:-}" ] && { mkdir -p "$WORKTREES"; args+=(--add-dir "$WORKTREES"); }
  # shellcheck disable=SC2086
  (cd "$cwd" && claude "${args[@]}" $AGENT_EXTRA_FLAGS < /dev/null > "$out" 2> "$err")
}
