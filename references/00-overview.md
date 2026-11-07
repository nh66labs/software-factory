# 00 - Overview: how the factory works

## The idea in one paragraph
A product is a list of **stories**. Each story is built by a fresh headless agent run in its own git worktree, delivered
through a line that proves the exact commit before the integration branch moves, and released to production automatically.
Several **lanes** run in parallel; one **supervisor** keeps them healthy; one **janitor** keeps the machine from filling; a
**coordinator** (an interactive agent session, or the human) watches a health report every 30 minutes and fixes faults at
once. Humans decide scope, money, accounts and acceptance. Everything else is done by agents and recorded.

## Roles
| Role | Who | Does | Never |
|---|---|---|---|
| Owner | human | scope, money, paid accounts/vendors, contracts, legal text, devices, acceptance, exceptions to their own rules | routine approvals, merging, unblocking |
| Coordinator | interactive agent session | discovery, plan, factory setup, the health loop, incident fixes, release announcements, decisions | build stories by hand while lanes run; approve its own authored work |
| Author | headless run | writes a flow, a technical plan, tests, or code for ONE story | review or approve its own output |
| Reviewer | headless run, fresh context | independent review with a checklist; fixes what is fixable and reports the rest | approve (the coordinator does, after reading the report) |
| Builder | headless run | implements one story in its worktree; leaves a commit | merge, push the integration/production branch |
| Fixer | headless run | resolves a rebase conflict or a failing critical test in the story's worktree | weaken a test |
| Verifier | script (a machine) | runs the critical tests on one exact commit, records the pass | change code |
| Supervisor / janitor | daemons | schedule, park, re-deliver, watchdog, clean | decide product questions |

## Data flow
```
 human <-> coordinator <-> brief, plan, decisions log
                         |
        queues/lane-*.txt (ordered story ids)           research/ plan/ docs/ (in the repo)
                         |
   drive.sh (one per lane) --run-agent--> headless agent in worktree wt/<story>  (build)
                         |                         |  commit on story/<id>
                         v                         v
                  deliver.sh (one at a time, priority on the heavy lock)
        rebase on integration -> record-critical (exact commit, fresh stack, no retries) -> tag e2e-critical/<sha>
        -> ff-merge integration -> push -> release.sh (ff production, push) -> post-release smoke check -> clean up
                         |
              deploy workflow refuses a production commit without the tag
   supervisor.sh: release-first scheduling, parking, re-delivery, stall + heavy watchdogs, lane restarts
   janitor.sh:    disk/cache/worktree/stack cleanup        health.sh: the report the coordinator acts on
```

## Branch model
`story/<id>` (one per story, in a worktree) -> `integration` (e.g. staging; always releasable because only proven commits
enter) -> `production` (e.g. main; moves only through `release.sh`; the push deploys). With a single environment set both
names equal; the proof still happens before the merge.

## The invariants (if one is false, stop and repair before building more)
1. Every commit on the integration branch has a recorded critical pass (`e2e-critical/<sha>`).
2. Production only moves by fast-forward from integration through `release.sh`; a git hook refuses any other move.
3. At most one heavy job runs per machine; a delivery's heavy jobs go before any story's.
4. Every agent run has a pid file; nothing is found by process name.
5. Every story has exactly one driver; a parked story has none.
6. `progress.log` is the single event stream: `<id> <EVENT> <text> <date time>`. Events: START, RETRY, INFRA-WAIT, DEFERRED,
   FAILED, DONE, REBASE-FIX, DELIVERY-FAILED, CRITICAL-E2E-FAILED, PUSH-PENDING, RELEASED, RELEASE-FAILED, PARKED, UNPARKED,
   STALL, HEAVY-KILLED, LOW-DISK, BUDGET-HOLD, QUEUE-EMPTY, STUCK.
7. Test stacks are isolated (unique name, ports, data) and always torn down.
8. The plan is read-only for agents; a wrong plan is fixed by a change request, never by code that invents behaviour.

## Where things live (in the target project)
```
.factory/
  factory.conf          the only adapter (stack commands, branches, limits)
  bin/                  the scripts (a copy: the project carries the exact version it ran)
  prompts/              build-story.md fix-run.md _common.md sweep.md spec-*.md review-*.md ...
  queues/<lane>.txt     ordered story ids, one per line
  state/                runtime only, git-ignored: progress.log supervisor.log janitor.log runs/ pids/ verdicts/
plan/ research/ docs/   the plan, the evidence, flows/TIPs/reviews/decisions
```
