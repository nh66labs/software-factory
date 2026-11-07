#!/usr/bin/env bash
# agent-smoke.sh   (`factory agent-smoke`)  ONE real, tiny agent run that proves what a stub cannot:
#   1. the agent CLI starts headless, is logged in and finishes with the RESULT line (adapter + parse-result);
#   2. it can create a worktree, edit, commit and run the project's fast gate command under the REAL permission settings;
#   3. a command that the settings DENY is refused (proves the settings are trusted and honoured, i.e. the rails hold);
#   4. nothing outside its worktree changed (the integration/production branches did not move).
# Costs a few cents. Run it after `factory init` on every machine, and again after changing permissions or the adapter.
# Exit 0 = ready for unattended runs; 1 = not ready (the reason is printed).
. "$(dirname "$0")/lib/common.sh"
cd "$REPO" || exit 1
id="SMOKE-$(date +%s)"; wt=$(story_wt "$id"); br=$(story_branch "$id")
before_int=$(git rev-parse "$INTEGRATION_BRANCH"); before_prod=$(git rev-parse "$PRODUCTION_BRANCH")
fast=${CMD_GATE_FAST:-}
prompt="$RUNS/$id.build.prompt"
cat > "$prompt" <<EOP
This is a smoke test of the unattended-agent setup. Do exactly these steps, nothing else.
1. Run: git worktree add $wt -b $br $INTEGRATION_BRANCH   then work only in $wt.
2. Create the file factory-smoke.txt in $wt containing the single line: smoke ok
3. Run the project's fast gate command from $wt: ${fast:-"(none configured: skip this step)"}
4. Try to run this command, which the project's settings must DENY: git -C $wt status   (a refusal is the expected, correct outcome; do not work around it). Note whether it was refused or ran.
5. Commit factory-smoke.txt on branch $br with a message saying "smoke: gate=<pass|fail|skipped> deny=<refused|ran>".
Do not merge, push, or touch any other branch or file. ${COMMIT_TRAILERS}
Your final message must end with exactly one line: RESULT: DONE <short sha>   (or RESULT: BLOCKED <reason>).
EOP
echo "agent-smoke: running one real $AGENT_ADAPTER run (a few minutes at most)"
line=$("$FACTORY_BIN/run-agent.sh" build "$id" "$prompt" "$REPO" "${AGENT_EFFORT:-medium}")
echo "agent-smoke: result: $line"
bad=0
case "$line" in
  DONE*) echo "OK    the agent ran headless and ended with a RESULT line" ;;
  INFRA*) echo "FAIL  the agent could not run ($line): network, login, usage limit or the host refused to launch it"; bad=1 ;;
  *) echo "FAIL  the agent did not finish cleanly: $line"; bad=1 ;;
esac
if git rev-parse -q --verify "refs/heads/$br" >/dev/null 2>&1 && [ "$(git rev-list --count "$INTEGRATION_BRANCH..$br")" -gt 0 ]; then
  msg=$(git log -1 --format=%B "$br" 2>/dev/null)
  git show "$br:factory-smoke.txt" 2>/dev/null | grep -q "smoke ok" && echo "OK    it created, edited and committed in its own worktree" || { echo "FAIL  the smoke file was not committed"; bad=1; }
  case "$msg" in *"deny=refused"*) echo "OK    a denied command was refused: the settings are trusted and honoured" ;;
                 *"deny=ran"*) echo "FAIL  a command the settings deny RAN: the deny rules are not in force (trust dialog not accepted? settings missing?)"; bad=1 ;;
                 *) echo "WARN  the deny test result was not reported" ;; esac
  case "$msg" in *"gate=pass"*) echo "OK    the project's fast gate ran and passed under the real permissions" ;; *"gate=skipped"*) echo "WARN  no fast gate configured" ;; *) echo "FAIL  the fast gate did not pass for the agent: $msg"; bad=1 ;; esac
else
  echo "FAIL  no commit was made on $br"; bad=1
fi
[ "$(git rev-parse "$INTEGRATION_BRANCH")" = "$before_int" ] && [ "$(git rev-parse "$PRODUCTION_BRANCH")" = "$before_prod" ] && echo "OK    the integration and production branches did not move" || { echo "FAIL  a protected branch moved"; bad=1; }
git worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"; git worktree prune; git branch -D "$br" >/dev/null 2>&1 || true
if [ $bad = 0 ]; then echo "agent-smoke: READY for unattended runs"; else echo "agent-smoke: NOT READY (see FAIL lines; stderr of the run: state/runs/$id.build.err)"; fi
exit $bad
