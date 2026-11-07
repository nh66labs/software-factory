# Adapter for Claude Code (headless): `claude -p`. Defines agent_exec <prompt-file> <cwd> <out-json> <err-file> <effort>.
#
# Permission mode: a headless run cannot answer a permission prompt, and a command that "asks" simply fails for it
# (a fix run once reported BLOCKED because `reset` was on the ask list). Run unattended agents on a dedicated machine or
# VM that holds no credentials you mind losing, in bypassPermissions mode, and put the real rails in project settings:
# deny rules for destructive git/push forms, hooks that protect the production branch and the rails files, and prompts
# that name the allowed equivalent of every command that is on the ask list. Deny rules and hooks still apply.
#
# Trust: project settings (allow lists included) are IGNORED in a directory whose trust dialog was never accepted
# ("Ignoring N permissions.allow entries ... workspace has not been trusted" in the run's stderr). Accept the dialog once
# interactively in the checkout the runs start from, or set hasTrustDialogAccepted for that path in the user config.
agent_exec() {
  local prompt=$1 cwd=$2 out=$3 err=$4 effort=$5
  local args
  args=(-p "$(cat "$prompt")" --output-format json --permission-mode "${CLAUDE_PERMISSION_MODE:-bypassPermissions}")
  [ -n "$AGENT_MODEL" ] && args+=(--model "$AGENT_MODEL")
  [ -n "$effort" ] && args+=(--effort "$effort")
  # shellcheck disable=SC2086
  (cd "$cwd" && claude "${args[@]}" $AGENT_EXTRA_FLAGS > "$out" 2> "$err")
}
