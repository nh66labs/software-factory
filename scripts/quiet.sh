#!/usr/bin/env bash
# quiet.sh pause|resume: freeze (SIGSTOP) or continue every registered story run (build and fix) and its whole process
# tree, so the critical tests run on an otherwise idle machine and their timings mean something.
#
# Two details that were each learned the hard way:
#  - Only pid files are trusted (lib/common.sh pid registry). Matching process names once killed an entire lane
#    because its command line merely listed the story being parked.
#  - Freezing an agent does not freeze the test and build containers it already started: they keep burning CPU and the
#    "idle machine" is not idle. They are THROTTLED to one CPU while paused (a frozen browser test would time out on
#    resume) and released on resume. Verification stacks and the live demo are never touched.
#
# Resume belongs to ONE place: the end of a delivery (its EXIT trap) or the supervisor when nothing is waiting. A resume
# in the middle of a delivery lets a build start its own gate and the delivery then waits a whole gate for the machine.
FACTORY_ALLOW_NO_CONF=${FACTORY_ALLOW_NO_CONF:-}
. "$(dirname "$0")/lib/common.sh"

throttle_targets() {
  [ "$STACK_ENGINE" = docker ] || return 0
  docker ps --format '{{.ID}} {{.Names}}' 2>/dev/null | awk -v p="$STACK_NAME_PREFIX" -v v="$VERIFY_STACK_PREFIX" \
    'index($2, p) == 1 && index($2, v) != 1 && $2 !~ /-demo/ {print $1}'
}
apply() {  # apply <STOP|CONT> <cpus>
  local kind name pid
  for kind in build fix; do
    list_runs "$kind" | while read -r name pid; do
      if [ "$1" = STOP ]; then pause_tree "$pid"; else resume_tree "$pid"; fi
    done
  done
  for c in $(throttle_targets); do docker update --cpus "$2" "$c" >/dev/null 2>&1 || true; done
}
case "${1:-}" in
  pause)  apply STOP 1 ;;
  resume) apply CONT 0 ;;
  *) echo "usage: quiet.sh pause|resume" >&2; exit 2 ;;
esac
