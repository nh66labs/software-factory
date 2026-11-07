# 09 - Operations runbook (the coordinator's job)

## Operating contract
- Run `factory health --fix` every 30 minutes (schedule it with the host agent's scheduler or a cron job that invokes the
  agent). Fix every WARN/FAIL immediately and WITHOUT asking: pipeline repairs are routine. Tell the owner only (1) a release
  went out - what is new, where to click - or (2) something is broken that you could not fix. When everything is OK say nothing.
- The coordinator does not build stories by hand while lanes run. It plans, decides, repairs the line, reviews, communicates.
- Keep the owner's time sacred: batch questions, recommend a default for each, accept silence as "your call" for technical
  items; never ask for approval of anything outside the owner-only list.

## Communication style (defaults; the brief may override)
Answer first. Short lines, one per item, no recap of the question, no background, no justification unless asked. For "is X in the
plan / built": `in the plan: yes/no; built: yes/no`. Status = last release (what, when), what is running, what is parked, what is
waiting, disk/machine. Never write essays. Never soften a failure: say what broke, what you did, what is still unverified.

### Release announcement (after every release)
```
Released <story title> (<sha>), deploy <ok/failed>.
New: <one line per user-visible change>.
Where: <screen / URL path>.
Unverified: <anything not covered>.
```

## The 30-minute loop
1. `factory health --fix`; read WARN/FAIL lines.
2. Hours since last RELEASED > 2 and stories waiting? -> find the cause in `state/runs/<story>.merge`: infrastructure error
   ('stack did not start', docker, disk, lock, dead driver) -> fix the line; test failures -> let the fix run work (or read the
   failure and decide); nothing happening -> restart the lane / re-deliver.
3. After a new release: check the deploy status; send the announcement.
4. Look at parked stories: read the failure, decide (fix the test, change request, drop, split the story), `factory unpark`.
5. Spend: `factory usage`; near the cap -> tell the owner once.
6. Capacity: load vs cores, free memory, disk. If lanes exceed capacity, reduce lanes (stop a lane marker) rather than
   hoping.

## Decision tree for common alarms
| Alarm | First look | Action |
|---|---|---|
| no release > 2h, stories waiting | `runs/<story>.merge` tail | stack-start failure -> fix infra; test failures -> fix run; nothing running -> `factory health --fix` |
| many critical failures at once | memory, load, leftover stacks, disk, network | stop leftovers, wait for quiet, rerun; do NOT touch tests yet |
| the same one test fails every time | the failure text | real defect (story's own test or a regression): fix run; if > `PARK_AFTER_MIN`, parked - read it yourself |
| `INFRA-WAIT` lines | network/API/usage limit | wait; confirm connectivity; if the usage limit: the lanes sleep and resume by themselves; tell the owner once |
| `HEAVY-KILLED` | which job, how long | investigate looping test; fix the cause |
| `LOW-DISK` | `df`, docker volumes, build caches | janitor ran? trim caches; remove stale worktrees; grow disk |
| supervisor/janitor dead | `factory health --fix` | restarted; look at `*.out` for why |
| PUSH-PENDING | `runs/<story>.merge` | usually a refused push (credentials/scope); fix and the next delivery retries |
| RELEASE-FAILED / POST-RELEASE-CHECK-FAILED | deploy log | roll back or fix forward now; alert the owner |
| lane not running | queue file, `.done` marker | the supervisor restarts it; if it dies repeatedly read `runs/lane-*.out` |

## When you change the pipeline
1. State the fault and the cause (one line).
2. Make the smallest change that removes the cause AND add a guard (check, limit, prompt line) so it cannot recur silently.
3. Test it: `scripts/selftest.sh`, then watch one real delivery.
4. Add or update the catalog entry (`08`).
5. Tell the owner in two lines what was wrong and that it is fixed (or not yet proven).

## Morning/evening routines
Start of session: `factory health`, last 20 lines of `progress.log`, parked list, deploy status, spend. End of session: leave
the loop scheduled, leave no manual lock or paused run behind, write the handover in `docs/handover.md` (what runs, what is
parked, what to watch).

## Measuring throughput honestly
Stories delivered per day = `RELEASED` lines per day (`grep RELEASED progress.log`); cost per story from `cost=$` lines; the
critical-run duration from `verdicts` timestamps. Report ranges from measured clean days; never promise a date from a plan
count alone. The limit is nearly always the single machine's capacity (one critical run at a time), then the agent's usage cap.

## What not to do
Do not weaken a test to make a release go. Do not bypass the deploy guard. Do not merge by hand into the integration or
production branch during a delivery. Do not "retry until green" in the critical run. Do not edit the plan to match the code.
Do not leave a lane paused. Do not start more lanes than the capacity formula allows.
