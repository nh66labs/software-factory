# 08 - Failure catalog: everything that went wrong, and the guard that now prevents it

Format: **Symptom** -> cause -> fix -> guard in this system. Add new entries in the same shape when you meet something new.

## A. The delivery line
**A1. The first full run on merged code was the release.** Stories passed alone, merged, and the release run failed 15 tests
-> nothing tested the combined result before it landed -> test the REBASED commit before the integration branch moves and
record the pass per commit -> `deliver.sh` + `record-critical.sh` + deploy guard.

**A2. Tests shared mutable state.** Two tests used the same calendar-day slot and corrupted each other's measured postings under
parallelism; fails only in full runs -> unique allocation of shared test resources -> a unit test scans the suite for duplicate
slots; prompts carry the rule; slots widened.

**A3. A test not updated when product behaviour changed.** A UI change (voiding now needs a reason) broke an old flow test in
another story -> the fix run owns repairing the old test (never weakening) -> `fix-run.md`; critical set runs on every delivery.

**A4. The integration branch itself was red.** A dependency advisory and a lint rule failed the full gate for every run ->
nobody owns the integration branch's health -> keep the gate green on the integration branch; scheduled audit; exceptions have
expiry dates -> `matrix`/audit schedule in 04.

**A5. Two actors wrote the main checkout at once** (a manual commit during a delivery; a second pusher process) -> one lock for
every write -> `state/deliver.lock`; manual writes take it.

**A6. Delivery failed on a rebase conflict in generated files** (API snapshots, client, migration numbers, translation
files, coverage matrix) -> hand-merging generated files -> regenerate with tooling; `merge-json-keys.py` merge driver; the fix
prompt says so.

**A7. A push gate ran beside a build's gate and the delivery waited a whole gate.** The delivery resumed the paused runs too
early (a second resume hidden inside the locked command) -> ONE resume, in the exit trap -> `deliver.sh`.

**A8. The release step ran, deploy was green, production was broken** -> a green deploy workflow only proves the script ran ->
`CMD_POST_RELEASE_CHECK` smoke test, alert on failure.

## B. Test infrastructure
**B1. Mass failures that looked like bugs (15 of 120, later 45 "Target crashed").** Causes in order of frequency: several heavy
suites at once (load 17 on 11 cores); leftover verification stacks consuming the VM's memory; low disk -> heavy lock, quiet
pause, teardown of every verification stack, capacity formula -> `heavy`, `quiet.sh`, `critical-e2e.sh` trap, `factory doctor`.
Rule: when many unrelated tests fail with crashes/timeouts, check the machine before the code.

**B2. Pausing the agents did not quiet the machine.** The agent processes were frozen but the test containers they had started
kept running at full CPU -> throttle those containers (not freeze: frozen browser tests time out on resume) -> `quiet.sh`.

**B3. The stack would not start ("has active endpoints").** Docker left a ghost network endpoint; the stack name could never
start again and removal failed silently; every release stalled for 14 hours -> a fresh stack name per verification run, skip
stuck names, always tear down, never rely on `down` succeeding -> `critical-e2e.sh`.

**B4. A wipe flag was ignored by the wrapper.** `down -v` did not pass `-v` on, so volumes survived and databases were
polluted across runs and disks filled -> test the wipe command; the wrapper forwards flags and refuses the destructive flag in
the live-demo checkout -> adapter contract in 11.

**B5. Stale data from a reused stack** ("242 customers vs 200 expected") -> the critical run always resets the stack; fix runs
are told how to wipe their own stack with allowed commands.

**B6. Timing flakes that only appear under load** (a default value arriving 5+ seconds after page load) -> readiness waits sized
for a loaded machine, event-based; never delete the assertion.

**B7. A single targeted E2E ran 137 minutes** (looping, or frozen while the laptop was offline) -> lower kill limit for targeted
E2E runs (45 min) than for gates -> `HEAVY_TARGETED_LIMIT_MIN`.

**B8. Coverage fell below the gate after many stories** -> every prompt carries the ratchet and the per-story coverage check;
scheduled coverage sweeps.

## C. Agent runs
**C1. Runs ended with no RESULT line.** The agent started a long command in the background and ended its turn -> foreground
rule in the common block; `BLOCKED no-result-line` is retried and counted.

**C2. A fix run reported BLOCKED "needs approval".** A command it needed was on the permission "ask" list; headless cannot
answer -> every prompt command is allowed or has an allowed equivalent; audit once -> 04 section 4.3.

**C3. Project permission settings silently ignored** ("Ignoring N permissions.allow entries: workspace has not been trusted") ->
accept the trust dialog once per machine in the checkout runs start from -> `factory doctor` warns.

**C4. Network outage/laptop sleep turned finished stories into failures.** Output was an API error; the driver counted failed
attempts and parked stories -> classify `INFRA` (network, API, usage limit, killed, empty output) and retry without counting;
keep the machine awake; alert once -> `parse-result.py`, `drive.sh`, `keepawake.sh`.

**C5. Retry counters were exhausted by infrastructure failures**, parking healthy stories for good -> counters renew after a
window; the stall watchdog clears them -> `supervisor.sh`.

**C6. The queue contained story ids that do not exist** (guessed ids) and agents were paid to discover it -> validate ids
against the plan before any run -> `story_exists` in `drive.sh`.

**C7. Two drivers on one story edited the same worktree** (a lane driver plus a re-delivery) -> one driver per story via a pid
file; the supervisor re-delivers only when no driver/fix/delivery is alive -> `drive.sh`, `supervisor.sh`.

**C8. The supervisor killed a whole lane** because its pattern matched a lane whose command line merely listed the parked
story -> never match processes by name; every run, lane and delivery has a pid file -> `lib/common.sh`.

**C9. A fix loop ran for a day on one story**, and "release first" scheduling paused every build behind it -> bounded fix loop,
parking after `PARK_AFTER_MIN`, parked stories get no run and no driver -> `supervisor.sh`.

**C10. The cost of long runs surprised the owner** -> cost per run in the log, `factory usage`, optional daily cap.

**C11. Sub-agents multiplied cost** -> prompts forbid sub-agents unless the owner allows; one run, one thread.

## D. Machines
**D1. A 95 GB build cache filled the disk.** The cleanup only ran "when idle", and the factory is never idle -> size-triggered
trim that is safe while builds run (`CMD_CACHE_TRIM`), plus volume/image/worktree cleanup -> `janitor.sh`.

**D2. Finished worktrees and stacks accumulated** -> the janitor removes worktrees whose branch is in the integration branch,
with their stacks.

**D3. Memory exhausted by leftover stacks** (eight containers each) -> teardown on exit; stop stale verification stacks.

**D4. macOS vs Linux differences broke scripts** (`pgrep -c`, `sed -i`, `stat -f`, bash 3.2) -> portability helpers in
`lib/common.sh`; `selftest.sh` runs on both.

**D5. A sleeping laptop dropped every connection at once** -> `keepawake.sh`; prefer an always-on machine.

## E. Operating the factory
**E1. The coordinator did not notice for hours.** Problems surfaced only when the owner asked -> a health report on a 30-minute
schedule, acted on without asking, plus watchdogs that need no human -> `health.sh`, supervisor.

**E2. Waiting for approval on pipeline repairs** -> repairs of the pipeline are routine: fix first, tell after.

**E3. Long essays as status updates annoyed the owner** -> answer first, one line per item, no recap; "in the plan: yes/no;
built: yes/no" for feature questions -> 09.

**E4. Pace promises without measurement** -> never give a date; compute throughput from `progress.log` over several clean days;
state the machine-bound limit honestly.

**E5. My own fixes caused the next failure** (fresh stack names left stacks running; a parking rule killed a whole lane; a pause
froze the lock holder) -> every pipeline change is exercised before it is relied on: run `selftest.sh`, then one real delivery,
and report the result in the same message.

**E6. A wipe/clean script was run in the wrong checkout** -> destructive flags refused in the main checkout; verification uses
its own worktrees.

**E7. A story was parked and forgotten** -> parked stories appear in every health report as WARN until looked at.

## F. Planning and process
**F1. Building from an unreviewed plan** -> plan review before freeze; parity check; independent reviewers.

**F2. Priority labels used as build order** -> only dependencies set order.

**F3. Agents invented behaviour not in the flow** -> trace-check both ways; change requests.

**F4. UI corrections fixed once and repeated elsewhere** -> a correction becomes a rule in the UI rules, applied everywhere.

**F5. Approval chores for the owner** -> batch questions; coordinator approves flows/TIPs after independent review; the
owner-only list is short and explicit.

## G. Found in the first use on a new project (a small static site)
**G1. The host blocked unattended agent runs.** The environment's safety classifier refused to launch a headless agent in
bypass-permissions mode ("creates an unsafe agent") even for a read-only review -> the factory cannot start lanes until the
human grants an explicit permission rule (or an alternative mode is chosen) -> ask for it in discovery (section E) and test one
headless run in phase 3 BEFORE planning on lanes; fallback: the coordinator builds the walking skeleton interactively through the
same gates and `factory deliver` (the delivery line does not care who wrote the commit).

**G2. `critical-e2e` passed the commit appended to the command string, but configs used `$1`.** The critical command now receives
the commit as `$1` and `$FACTORY_COMMIT`; scripts are referenced as `"$FACTORY_BIN/..."` because a fresh verification worktree
does not contain untracked project files (commit `.factory` or use the exported variable).

**G3. A formatter rewrote guard-rail files** (`.claude/settings.json`, workflows, rules file) in a story worktree, which is a
rails edit. -> the formatter's ignore list names every guard-rail and generated file from day one; `./run fmt` is never run
blindly in a story that must not touch them.

**G4. Empty directories are not in git**, so a fresh worktree lacked `src/styles` and files written into it failed -> a builder
creates directories it needs (`mkdir -p`), prompts say so.

**G5. A skeleton with navigation to sections that later stories add fails the link check.** -> a shrinking pending list
(`scripts/pending-anchors.json`): listed anchors may be missing until their story removes them, and a listed anchor that exists
fails the check, so the list can only shrink. General pattern: a ratchet for "temporarily allowed" gaps.

**G6. A real defect was found by the acceptance test, not by eye**: horizontal overflow at 375 px caused by a grid track growing
to its content. The test was kept; the CSS was fixed (`minmax(0, 1fr)`). Phone-width checks belong in the first story.

**G7. The plan was built from an AI summary of the reference page**, which turned three pricing tabs into two, missed a sticky
floating button and missed three video cards. A string-presence check could not see structure. The independent plan review found
all three -> build the inventory from the RAW evidence (markup, DOM, screenshots), never from a model's summary; the independent
plan review is mandatory, run as a headless reviewer (`templates/prompts/review-plan.md`) and applied by a different author run
(`plan-fix.md`) that verifies each finding against the raw evidence.

**G8. Headless runs in a new project had no permissions at all, and no deny list.** Claude Code ignores a project's
`.claude/settings.json` (allow AND deny) until the trust dialog is accepted interactively. -> the adapter passes the settings
explicitly (`--settings`), so allow/deny rules and hooks apply anyway; `factory agent-smoke` proves it with a deny test.

**G9. Agents could not edit files in their own worktree**: the worktrees live beside the repository and the agent may only edit
inside its start folder -> the adapter adds the worktrees folder (`--add-dir`).

**G10. The host refused to launch agents in bypass-permissions mode and refused edits that broaden the agent's own allow list.**
-> least privilege is the default (`acceptEdits` + an allow list that the human approves in phase 3); the allow list is written
once, by the human or with explicit approval, never widened by the coordinator on its own.

**G11. Two worktrees corrupted a shared dependency volume** (`npm ci` deletes node_modules first; two installs at once collide)
-> one dependency volume per lockfile hash and a host-side install lock; the coordinator never runs container commands beside a
live lane without the same lock.

**G12. `count=$(grep -c ... || echo 0)` produced "0\n0"** (grep -c prints 0 AND exits 1), corrupting a timestamp file: health
showed a 56-year release age -> never `|| echo 0` after `grep -c`; parse state files defensively.

**G13. Daemons started from a tool shell kept its stdin open, so the caller hung** -> every background start redirects
`< /dev/null`.

**G14. A one-epic plan put every story into one lane** -> `queue.py` deals stories by dependency affinity when there are fewer
areas than lanes; health ignores empty queue files.

**G15. The coordinator's own commit made the integration branch red**, and a refused push was ignored. Later a delivery's tag
push ran the pre-push gate on that red state and failed -> the coordinator's commits go through the same fast gate (never commit
around it); a refused push is a stop signal, never noise; the pre-push hook gates code pushes only (tag and factory-ref pushes
are not code and happen before the merge).

**G16. The release switched the shared main checkout to the production branch and back**, rewriting tracked files under the
running daemons (for a while the factory's own scripts and config were the older production versions) and touching the queue
files, which the supervisor read as "edited" and restarted finished lanes -> the release moves the production ref without a
checkout (`git fetch . integration:production`, fast-forward only); lane restarts compare queue CONTENT, not mtimes.

**G17. A stand-in deployment that served the previous commit made the post-release check fail after 18 minutes** - correctly:
the check compares the served version with the released commit. Keep that check strict; point it at the real deployment.
