# 06 - Orchestration: the scripts, state and scheduling

All scripts live in `scripts/` (copied to `<project>/.factory/bin` by `factory init`). They share `lib/common.sh`, read
`factory.conf`, run on bash 3.2+/python3 stdlib (macOS and Linux), find processes only through pid files, and write events to
`state/progress.log`.

## Commands (`factory help`)
`init`, `doctor`, `start`, `stop [--all]`, `status`, `health [--fix]`, `queue <lane> <ids>`, `park|unpark|retry <story>`,
`logs`, `usage`, `deliver <story>`, `release [--check-only]`.

## Script map
| Script | Role |
|---|---|
| `drive.sh [--lane L] ids...` | the lane driver: build -> deliver -> next; INFRA retries, deferral, fix loop, parking-aware, one driver per story |
| `run-agent.sh` + `adapters/*.sh` | one headless agent run, pid-registered; the only agent-specific code |
| `parse-result.py` | output -> `DONE sha` / `BLOCKED reason` / `INFRA reason` + cost line |
| `deliver.sh` | rebase, record pass, merge, push, release, refresh demo, clean (one at a time, priority) |
| `record-critical.sh`, `critical-e2e.sh`, `verdict-check.py` | prove the exact commit; tag the pass (local or remote verifier) |
| `release.sh` | production fast-forward + push + post-release smoke check |
| `heavy` | machine-wide lock with priority and stale-owner takeover |
| `quiet.sh` | pause/resume story runs (whole process tree) and throttle their containers while a delivery tests |
| `supervisor.sh` | release-first scheduling, parking, re-delivery, stall + heavy watchdogs, lane restarts |
| `janitor.sh` | disk, caches, finished worktrees, leftover verification stacks |
| `health.sh`, `preflight.sh`, `usage.sh`, `keepawake.sh` | report, doctor, cost, stay awake |
| `verifier-daemon.sh` | verification machine: answers candidate commits through the git remote |
| `install-hooks.sh`, `githooks/*` | production-branch guard, pre-push gate |
| `plan-check.py`, `queue.py`, `trace-check.py`, `merge-json-keys.py`, `verdict-from-*.py` | plan and test tooling |
| `selftest.sh` | the whole pipeline on a toy project with a stub agent |

## One story's life (what you will see in progress.log)
`START attempt 1` -> agent builds -> `DONE sha` is logged only after delivery succeeded. In between: `CRITICAL-E2E-FAILED` or
a rebase conflict -> `REBASE-FIX` (up to 3 short fix runs) -> `DONE ... (after fix run)`; otherwise `DELIVERY-FAILED`.
`RELEASED <sha> to production` is written by delivery; `DEFERRED` when a dependency is missing; `INFRA-WAIT` when the agent
could not run for infrastructure reasons (not counted); `PARKED` by the supervisor; `STALL`, `HEAVY-KILLED`, `LOW-DISK`,
`BUDGET-HOLD` by the daemons.

## Scheduling rules and why
1. **One heavy job at a time** (`heavy`): the full gate, end-to-end suites and the critical run each start a stack; several
   together starve the machine and produce failures that look like product bugs.
2. **Priority**: a delivery's tests, push gate and release go before every ordinary waiter (`FACTORY_HEAVY_PRIORITY=1`).
3. **Quiet pause**: once the delivery holds the lock, all story runs are paused (process tree frozen, their containers throttled
   to one CPU) so the critical run's timings mean something. There is ONE resume: the delivery's exit trap. A resume earlier
   lets a build start its own gate and the delivery then waits a whole gate for the machine.
4. **Release first**: while no delivery runs, at most `MAX_FIX_RUNS` fix runs go and new builds wait while any fix run exists.
   A run whose process tree holds the lock is never stopped.
5. **Parking**: a story in its fix loop for `PARK_AFTER_MIN` is parked (marker file, run killed, owner alerted, worktree kept).
   A parked story is skipped by drivers and the supervisor until `factory unpark`. Without a bound, one stubborn story paused every
   build behind it for a day.
6. **Re-delivery**: built stories whose delivery failed are delivered again (limited per window; the window renews, because
   attempts burned on infrastructure faults must not park a story for good).
7. **Stall watchdog**: no release for `RELEASE_STALL_MIN` while stories wait -> log, alert, clear counters, re-deliver.
8. **Heavy watchdog**: a gate/critical job over `HEAVY_LIMIT_MIN`, a targeted E2E over `HEAVY_TARGETED_LIMIT_MIN`, is killed.
9. **Infrastructure vs product failures**: `INFRA` results (network, API down, usage limit, killed run) never consume an attempt;
   a day of ENOTFOUND once turned finished stories into failures.
10. **Budget**: `DAILY_BUDGET_USD` pauses lanes instead of spending past the cap.

## State files (`state/`, never in git)
`progress.log`, `supervisor.log`, `janitor.log`; `runs/<story>.{build,fix}.{json,err,prompt}`, `<story>.merge` (rebase + test
output of the last delivery), `pids/<kind>.<name>`; `verdicts/<sha>.json`; markers `.parked.<id>`, `.fixing.<id>`,
`.redeliver.<id>`, `.run.<id>`, `.release-stamp`, `lane-<name>.done|.stopped`; `deliver.lock/`.

## Starting and stopping
`factory doctor` -> `factory start` (keepawake, supervisor, janitor) -> `factory queue lane-1 ST-...` or drop `queues/lane-1.txt`;
the supervisor starts lanes within 2 minutes. Editing a queue file restarts a finished lane. `factory stop --all` stops everything
(agents included); in-flight worktrees stay, and the same queue resumes where it left off.

## Manual writes to the main checkout
Take the delivery lock first (`lock_take` on `state/deliver.lock`) - a manual commit during a delivery corrupts its rebase and
merge. Prefer to make fixes through a worktree and a delivery.
