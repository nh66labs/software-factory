#!/usr/bin/env bash
# selftest.sh   Proves the orchestration works end to end on a throw-away toy project with a STUB agent (no model, no
# network, no docker): two parallel lanes build, rebase, test, merge, release, clean up; a rebase conflict and a failing
# critical test are each repaired by a fix run; the heavy lock serialises and honours priority; the supervisor parks a
# stuck story; the production-branch guard refuses a stray move; the plan tools run.
#   scripts/selftest.sh [keep]     keep = do not delete the temp directory (printed at the end)
# Runs on macOS and Linux with git, bash 3.2+, python3. Takes about a minute.
set -u
SRC=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/factory-selftest.XXXXXX")
PASS=0; FAILN=0
ok()   { PASS=$((PASS + 1)); echo "  ok   $*"; }
bad()  { FAILN=$((FAILN + 1)); echo "  FAIL $*"; }
check() { local what=$1; shift; if "$@" >/dev/null 2>&1; then ok "$what"; else bad "$what"; fi; }
cleanup() { [ "${1:-}" = keep ] && { echo "kept: $T"; return; }; rm -rf "$T"; }
trap 'cleanup "${KEEP:-}"' EXIT
[ "${1:-}" = keep ] && KEEP=keep

echo "== toy project in $T"
git init -q --bare "$T/origin.git"
git init -q -b main "$T/proj"
cd "$T/proj" || exit 1
git config user.email t@example.invalid; git config user.name selftest
echo "line one" > shared.txt
cat > gate.sh <<'EOS'
#!/bin/sh
exit 0
EOS
cat > e2e-critical.sh <<'EOS'
#!/bin/sh
# toy critical test: fails when any feature file contains BREAK; writes the verdict like a real runner would
sha=$1
if grep -rq BREAK features 2>/dev/null; then
  printf '{"commit":"%s","ok":false,"passed":2,"failed":1,"retries":0,"reasons":["FAILED: feature contains BREAK"]}' "$sha" > verdict.json; exit 1
fi
printf '{"commit":"%s","ok":true,"passed":3,"failed":0,"retries":0,"reasons":[]}' "$sha" > verdict.json
EOS
mkdir -p plan/epics
cat > plan/epics/EP-A.md <<'EOS'
### ST-A-1 · first
- Depends on: none
- Acceptance:
  - AC1 file exists
### ST-A-2 · second (conflicts with the first on shared.txt)
- Depends on: none
- Acceptance:
  - AC1 file exists
### ST-C-1 · third (breaks the critical test once)
- Depends on: none
- Acceptance:
  - AC1 file exists
EOS
cat > plan/epics/EP-B.md <<'EOS'
### ST-B-1 · depends on ST-A-1
- Depends on: ST-A-1
- Acceptance:
  - AC1 file exists
EOS
printf '.factory/\n' > .git/info/exclude
git add -A && git commit -q -m init
git branch staging
git remote add origin "$T/origin.git"
git push -q origin main staging
mkdir -p "$T/proj-wt/.." ; git rev-parse HEAD > "$T/initsha"

echo "== factory init"
bash "$SRC/factory" init "$T/proj" --name toy >/dev/null
F="$T/proj/.factory"
sed -i.bak -e "s#^AGENT_ADAPTER=.*#AGENT_ADAPTER=generic#" \
  -e "s#^PLAN_DIR=.*#PLAN_DIR=$T/proj/plan#" \
  -e "s#^HEAVY_LOCK=.*#HEAVY_LOCK=$T/heavy.lock#" \
  -e "s#^CMD_GATE_FULL=.*#CMD_GATE_FULL='sh gate.sh'#" \
  -e "s#^CMD_GATE_FAST=.*#CMD_GATE_FAST='sh gate.sh'#" \
  -e "s#^CMD_STACK_RESET=.*#CMD_STACK_RESET='true'#" \
  -e "s#^CMD_E2E_CRITICAL=.*#CMD_E2E_CRITICAL='sh e2e-critical.sh "\$1"'#" \
  -e "s#^E2E_VERDICT_FILE=.*#E2E_VERDICT_FILE=verdict.json#" "$F/factory.conf" && rm -f "$F/factory.conf.bak"
printf 'AGENT_CMD="sh %s/stub-agent.sh"\nINFRA_RETRY_SLEEP=1\nDEFER_POLL=2\n' "$T" >> "$F/factory.conf"
# the stub agent: reads the prompt on stdin; builds, or repairs, depending on which prompt it got
cat > "$T/stub-agent.sh" <<'EOS'
#!/bin/sh
prompt=$(cat)
story=$(printf '%s\n' "$prompt" | sed -n 's/^You are building ONE story .*Story: \(.*\)\.$/\1/p;s/^Story \([A-Za-z0-9-]*\) is finished.*/\1/p' | head -1)
kind=build; printf '%s' "$prompt" | grep -q 'is finished on branch' && kind=fix
wt=$(printf '%s\n' "$prompt" | sed -n 's/^1\. From the main checkout: `git worktree add \([^ ]*\) .*/\1/p;s/^.*in the worktree \([^ ,]*\),.*/\1/p' | head -1)
if [ "$kind" = build ]; then
  dep=$(printf '%s' "$story" | sed -n 's/^ST-B-1$/ST-A-1/p')
  if [ -n "$dep" ] && ! git -C "$PWD" show "staging:features/$dep.txt" >/dev/null 2>&1; then echo "RESULT: BLOCKED deps $dep"; exit 0; fi
  base=staging; [ "$story" = ST-A-2 ] && base=$(cat "$(dirname "$wt")/../initsha" 2>/dev/null || echo staging)
  git worktree add "$wt" -b "story/$story" "$base" >/dev/null 2>&1 || true
  cd "$wt" || { echo "RESULT: BLOCKED no worktree"; exit 0; }
  mkdir -p features; echo "feature $story" > "features/$story.txt"
  case "$story" in
    ST-A-1) echo "line from A1" >> shared.txt ;;
    ST-A-2) echo "line from A2" >> shared.txt ;;
    ST-C-1|ST-R-2) echo "BREAK" >> "features/$story.txt" ;;
  esac
  git add -A && git commit -q -m "$story: built" && echo "RESULT: DONE $(git rev-parse --short HEAD)"
else
  cd "$wt" || { echo "RESULT: BLOCKED no worktree"; exit 0; }
  if [ -d "$(git rev-parse --git-dir)/rebase-merge" ] || [ -d "$(git rev-parse --git-dir)/rebase-apply" ]; then
    printf 'line one\nline from A1\nline from A2\n' > shared.txt; git add shared.txt; GIT_EDITOR=true git rebase --continue >/dev/null 2>&1
  fi
  if [ -f "features/$story.txt" ] && grep -q BREAK "features/$story.txt"; then sed -i.bak '/BREAK/d' "features/$story.txt"; rm -f "features/$story.txt.bak"; git add -A; git commit -q -m "$story: fix the failing critical test"; fi
  echo "RESULT: DONE $(git rev-parse --short HEAD)"
fi
EOS
check "install-hooks" bash "$F/bin/install-hooks.sh" "$T/proj"

echo "== static: plan tools"
check "plan-check passes" python3 -I "$F/bin/plan-check.py" --plan "$T/proj/plan" --inventory /nonexistent
python3 -I "$F/bin/queue.py" --plan "$T/proj/plan" --lanes 2 | sed 's/^/     /'

echo "== unit: parse-result"
printf '%s' '{"result":"all done\nRESULT: DONE abc1234","num_turns":3,"total_cost_usd":1.5,"modelUsage":{"m":{"inputTokens":10,"outputTokens":5}}}' > "$T/r1.json"
check "DONE parsed with cost" sh -c "python3 -I '$F/bin/parse-result.py' '$T/r1.json' | grep -q '^DONE abc1234 | turns=3 tokens=15 out=5 cost=\$1.50'"
printf '%s' '{"is_error":true,"api_error":"connection_failed","result":"API Error: Can'"'"'t reach the API server (ENOTFOUND)"}' > "$T/r2.json"
check "network failure is INFRA (not counted)" sh -c "python3 -I '$F/bin/parse-result.py' '$T/r2.json' | grep -q '^INFRA'"
printf '%s' '{"result":"I will check when the tests finish."}' > "$T/r3.json"
check "no RESULT line is BLOCKED no-result-line" sh -c "python3 -I '$F/bin/parse-result.py' '$T/r3.json' | grep -q '^BLOCKED no-result-line'"
printf '%s' '{"result":"You have hit your usage limit. Resets at 5pm."}' > "$T/r4.json"
check "usage limit is INFRA" sh -c "python3 -I '$F/bin/parse-result.py' '$T/r4.json' | grep -q '^INFRA'"

echo "== unit: heavy lock serialises and honours priority"
H="$T/hl"; export HEAVY_LOCK="$H"
( "$F/bin/heavy" sh -c 'echo A-start >> '"$T"'/order; sleep 3; echo A-end >> '"$T"'/order' 2>/dev/null ) 2>/dev/null &
sleep 1
( "$F/bin/heavy" sh -c 'echo B >> '"$T"'/order' 2>/dev/null ) 2>/dev/null &
sleep 1
( FACTORY_HEAVY_PRIORITY=1 "$F/bin/heavy" sh -c 'echo P >> '"$T"'/order' 2>/dev/null ) 2>/dev/null &
wait
check "heavy order A-start, A-end, P (priority), B" sh -c "[ \"\$(tr '\n' ' ' < '$T/order')\" = 'A-start A-end P B ' ]"
unset HEAVY_LOCK

echo "== end to end: two lanes, conflict, failing critical test"
( cd "$F/bin" && ./drive.sh --lane one ST-A-1 ST-C-1 > "$T/lane-one.out" 2>&1 ) &
( cd "$F/bin" && ./drive.sh --lane two ST-A-2 ST-B-1 > "$T/lane-two.out" 2>&1 ) &
wait
LOG="$F/state/progress.log"
for s in ST-A-1 ST-A-2 ST-C-1 ST-B-1; do check "$s released" grep -qE "^$s RELEASED " "$LOG"; done
check "the rebase conflict (whichever of A-1/A-2 lost the race) went through a fix run" grep -qE "^ST-A-[12] REBASE-FIX " "$LOG"
check "failing critical test blocked the delivery first" grep -qE "^ST-C-1 CRITICAL-E2E-FAILED " "$LOG"
check "dependent story was deferred then built" sh -c "grep -qE '^ST-B-1 DEFERRED ' '$LOG' || grep -qE '^ST-B-1 DONE ' '$LOG'"
git -C "$T/proj" fetch -q origin
check "production has all four features" sh -c "cd '$T/proj' && for s in ST-A-1 ST-A-2 ST-C-1 ST-B-1; do git cat-file -e origin/main:features/\$s.txt || exit 1; done"
check "production has no BREAK" sh -c "cd '$T/proj' && ! git grep -q BREAK origin/main -- features"
check "shared.txt merged both sides" sh -c "cd '$T/proj' && git show origin/main:shared.txt | grep -q 'line from A1' && git show origin/main:shared.txt | grep -q 'line from A2'"
check "production head carries a recorded critical pass" sh -c "cd '$T/proj' && git ls-remote --tags origin \"refs/tags/e2e-critical/\$(git rev-parse origin/main)\" | grep -q ."
check "every RELEASED commit has a recorded critical pass" sh -c "cd '$T/proj' && for short in \$(sed -n 's/^[A-Z0-9-]* RELEASED \\([0-9a-f]*\\) .*/\\1/p' '$LOG'); do full=\$(git rev-parse \$short) && git ls-remote --tags origin \"refs/tags/e2e-critical/\$full\" | grep -q . || exit 1; done"
check "worktrees were removed" sh -c "[ -z \"\$(ls '$T/proj-wt' 2>/dev/null | grep -v verify-)\" ]"
check "no stray pid files" sh -c "[ -z \"\$(ls '$F/state/pids' 2>/dev/null)\" ]"
check "main checkout is clean on the integration branch" sh -c "cd '$T/proj' && [ -z \"\$(git status --porcelain --untracked-files=no)\" ] && [ \"\$(git branch --show-current)\" = staging ]"

echo "== deploy guard (templates/ci/check-e2e-marker.sh)"
GUARD="$SRC/../templates/ci/check-e2e-marker.sh"
git clone -q "$T/origin.git" "$T/guardclone" 2>/dev/null
prodsha=$(git -C "$T/guardclone" rev-parse origin/main)
check "guard accepts a commit with a recorded pass" sh -c "cd '$T/guardclone' && bash '$GUARD' $prodsha"
check "guard refuses a commit with no recorded pass" sh -c "cd '$T/guardclone' && ! bash '$GUARD' 0000000000000000000000000000000000000000"
check "guard allows an unverified commit only with a reason" sh -c "cd '$T/guardclone' && bash '$GUARD' 0000000000000000000000000000000000000000 'owner says go' 2>&1 | grep -q 'owner says go'"

echo "== guard: the production branch refuses a stray move"
cd "$T/proj" || exit 1
git switch -q main 2>/dev/null
[ "$(git branch --show-current)" = main ] || bad "could not switch to main to attempt the stray commit"
git commit -q --allow-empty -m "stray" 2>/dev/null
if git -C "$T/proj" rev-parse main >/dev/null 2>&1 && [ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ]; then ok "stray commit on main refused"; else bad "stray commit on main was accepted"; fi
git switch -q staging 2>/dev/null

echo "== supervisor: parks a story stuck in its fix loop"
sleep 600 & fakepid=$!
echo "$fakepid" > "$F/state/pids/fix.ST-STUCK-1"
: > "$F/state/.fixing.ST-STUCK-1"; touch -t 202001010000 "$F/state/.fixing.ST-STUCK-1"
bash "$F/bin/supervisor.sh" --once
check "story parked" test -f "$F/state/.parked.ST-STUCK-1"
sleep 1
if kill -0 "$fakepid" 2>/dev/null; then bad "fix run of the parked story was not killed"; kill "$fakepid" 2>/dev/null; else ok "fix run of the parked story was killed"; fi
wait "$fakepid" 2>/dev/null
rm -f "$F/state/pids/fix.ST-STUCK-1" "$F/state/.parked.ST-STUCK-1" "$F/state/.fixing.ST-STUCK-1"

echo "== quiet pause/resume and release-first scheduling (real processes, pid files)"
mkdir -p "$F/state/pids"
( sleep 300 & echo $! > "$T/b.child"; wait ) & bpid=$!      # a "build run" with a child process
( sleep 300 & echo $! > "$T/f.child"; wait ) & fpid=$!      # a "fix run" with a child process
sleep 1
echo "$bpid" > "$F/state/pids/build.ST-Q-1"; echo "$fpid" > "$F/state/pids/fix.ST-Q-2"
state_of() { ps -o stat= -p "$1" 2>/dev/null | cut -c1; }
bash "$F/bin/quiet.sh" pause
check "quiet pause froze the build run and its child" sh -c "[ \"\$(ps -o stat= -p $bpid | cut -c1)\" = T ] && [ \"\$(ps -o stat= -p \$(cat '$T/b.child') | cut -c1)\" = T ]"
check "quiet pause froze the fix run" sh -c "[ \"\$(ps -o stat= -p $fpid | cut -c1)\" = T ]"
bash "$F/bin/quiet.sh" resume
check "quiet resume continued both" sh -c "[ \"\$(ps -o stat= -p $bpid | cut -c1)\" != T ] && [ \"\$(ps -o stat= -p $fpid | cut -c1)\" != T ]"
bash "$F/bin/supervisor.sh" --once
check "release first: a fix run exists, so the build run is held back" sh -c "[ \"\$(ps -o stat= -p $bpid | cut -c1)\" = T ] && [ \"\$(ps -o stat= -p $fpid | cut -c1)\" != T ]"
rm -f "$F/state/pids/fix.ST-Q-2"
bash "$F/bin/supervisor.sh" --once
check "no fix run left: the build run is resumed" sh -c "[ \"\$(ps -o stat= -p $bpid | cut -c1)\" != T ]"
kill_all() { for p in "$@"; do pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; done; }
kill_all "$bpid" "$fpid"; wait "$bpid" "$fpid" 2>/dev/null
rm -f "$F/state/pids/build.ST-Q-1" "$F/state/pids/fix.ST-Q-2"

echo "== supervisor restarts a dead lane from its queue file"
mkdir -p "$F/queues"; printf 'ST-ZZ-9\n' > "$F/queues/ghost.txt"
bash "$F/bin/supervisor.sh" --once
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$F/state/lane-ghost.done" ] && break; sleep 1; done
check "lane ghost was restarted and rejected the story id that is not in the plan" grep -qE "^ST-ZZ-9 FAILED unknown story" "$LOG"
check "the lane marked itself done" test -f "$F/state/lane-ghost.done"
rm -f "$F/queues/ghost.txt" "$F/state/lane-ghost.done"

echo "== health report"
bash "$F/bin/health.sh" --short | sed 's/^/     /'
check "health runs (exit 0..2)" sh -c "bash '$F/bin/health.sh' >/dev/null; [ \$? -le 2 ]"

echo "== remote verification: a verifier machine answers through the git remote"
cat >> "$T/proj/plan/epics/EP-A.md" <<'EOS'
### ST-R-1 · remote pass
- Depends on: none
- Acceptance:
  - AC1 file exists
### ST-R-2 · remote failure then fix
- Depends on: none
- Acceptance:
  - AC1 file exists
EOS
( cd "$T/proj" && git switch -q staging && git add -A && git commit -q -m "plan: remote stories" && git push -q origin staging )
sed -i.bak -e 's#^VERIFY_MODE=.*#VERIFY_MODE=remote#' "$F/factory.conf" && rm -f "$F/factory.conf.bak"
printf 'VERIFY_TIMEOUT_MIN=3\n' >> "$F/factory.conf"
git clone -q "$T/origin.git" "$T/verifier" && (cd "$T/verifier" && git config user.email t@example.invalid && git config user.name selftest && git branch -q staging origin/staging 2>/dev/null; true)
bash "$SRC/factory" init "$T/verifier" --name toyverifier >/dev/null
V="$T/verifier/.factory"
sed -i.bak -e "s#^HEAVY_LOCK=.*#HEAVY_LOCK=$T/heavy-v.lock#" -e "s#^CMD_STACK_RESET=.*#CMD_STACK_RESET='true'#" \
  -e "s#^CMD_E2E_CRITICAL=.*#CMD_E2E_CRITICAL='sh e2e-critical.sh "\$1"'#" -e "s#^E2E_VERDICT_FILE=.*#E2E_VERDICT_FILE=verdict.json#" "$V/factory.conf" && rm -f "$V/factory.conf.bak"
( cd "$V/bin" && FACTORY_VERIFIER=1 ./verifier-daemon.sh > "$T/verifier.out" 2>&1 ) &
verifier_pid=$!
( cd "$F/bin" && ./drive.sh --lane remote ST-R-1 ST-R-2 > "$T/lane-remote.out" 2>&1 )
kill "$verifier_pid" 2>/dev/null; pkill -P "$verifier_pid" 2>/dev/null; wait "$verifier_pid" 2>/dev/null
check "ST-R-1 released with the verifier's pass" grep -qE "^ST-R-1 RELEASED " "$LOG"
check "verifier rejected the BREAK commit" grep -qE "^ST-R-2 CRITICAL-E2E-FAILED " "$LOG"
check "fix run repaired it and the verifier then passed" grep -qE "^ST-R-2 RELEASED " "$LOG"
check "verifier log shows a FAIL and a PASS" sh -c "grep -q FAIL '$V/state/verifier.log' && grep -q PASS '$V/state/verifier.log'"

echo
echo "selftest: $PASS passed, $FAILN failed"
[ $FAILN -eq 0 ]
