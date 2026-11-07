# Adapter for the Codex CLI (headless). Check the flags against the installed version (`codex exec --help`): the
# contract is only that the run prints the final message, which must end with the RESULT line.
agent_exec() {
  local prompt=$1 cwd=$2 out=$3 err=$4 effort=$5
  local args
  args=(exec --full-auto)
  [ -n "$AGENT_MODEL" ] && args+=(--model "$AGENT_MODEL")
  # shellcheck disable=SC2086
  (cd "$cwd" && codex "${args[@]}" $AGENT_EXTRA_FLAGS "$(cat "$prompt")" > "$out" 2> "$err")
}
