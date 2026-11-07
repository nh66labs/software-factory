#!/usr/bin/env bash
# run-agent.sh <build|fix> <story> <prompt-file> <cwd> [effort]
# Runs one headless agent run, registers its pid (so it can be paused, parked and counted), keeps its output under
# state/runs/ and prints the parse-result line. The adapter (adapters/<AGENT_ADAPTER>.sh) is the only part that knows
# which agent CLI is used; swapping the agent never touches the driver.
. "$(dirname "$0")/lib/common.sh"
kind=$1 story=$2 prompt=$3 cwd=$4 effort=${5:-$AGENT_EFFORT}
adapter="$FACTORY_BIN/adapters/$AGENT_ADAPTER.sh"
[ -f "$adapter" ] || { echo "BLOCKED no-adapter $AGENT_ADAPTER"; exit 0; }
. "$adapter"
out="$RUNS/$story.$kind.json"; err="$RUNS/$story.$kind.err"
pid_register "$kind" "$story"
trap 'pid_unregister "$kind" "$story"' EXIT
rm -f "$out"
agent_exec "$prompt" "$cwd" "$out" "$err" "$effort"
parse_result "$out"
