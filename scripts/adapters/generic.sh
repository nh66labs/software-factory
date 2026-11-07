# Adapter for any agent that reads the prompt on stdin and prints its final message (ending with the RESULT line) on
# stdout. Set AGENT_CMD in factory.conf, for example AGENT_CMD="my-agent --headless".
agent_exec() {
  local prompt=$1 cwd=$2 out=$3 err=$4 effort=$5
  [ -n "${AGENT_CMD:-}" ] || { echo "AGENT_CMD is not set" > "$err"; : > "$out"; return 0; }
  (cd "$cwd" && sh -c "$AGENT_CMD" < "$prompt" > "$out" 2> "$err")
}
