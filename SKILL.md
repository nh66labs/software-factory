---
name: software-factory
description: Run an autonomous software factory that takes a product idea from discovery and research to a continuously tested, released product. Use when asked to build a whole product (or a large body of features) with unattended coding agents; to research and reverse-engineer reference software and turn it into a dependency-ordered plan; to set up the headless build/test/release pipeline (lanes, delivery, critical end-to-end gate, supervisor, janitor, deploy guard) for any project; or to operate and repair such a pipeline. Not for a single small change in an existing repo.
---

# Software factory

A factory is: a **plan** (stories with acceptance criteria, ordered by dependency) + **headless agent runs** that build one
story each in an isolated worktree + a **delivery line** that proves every commit before it moves + **supervision** that keeps
it all moving without a human watching. The human owns scope, money, accounts and acceptance; everything else is decided,
done and recorded by agents.

This skill carries the complete, proven system: scripts (`scripts/`), prompt and document templates (`templates/`), and the
knowledge (`references/`), including the failure catalog of everything that went wrong before and how it is now prevented.
Nothing here is specific to a product, a stack or a machine; the one adapter file is `factory.conf`.

## Hard rules (never negotiable, in every phase)
1. **Prove the exact commit before it moves.** The critical end-to-end tests pass on the rebased commit, with no retries,
   before the integration branch moves; the pass is recorded as a tag; the deploy refuses a commit without it.
2. **Never weaken a check to pass it.** No deleted, skipped or loosened test, no relaxed threshold, no accepted contradicting
   snapshot. Fix the cause. Expected values for money/dates/permissions are computed independently, never read back.
3. **The writer is never the reviewer is never the approver.** Independent sessions review flows, plans and code.
4. **Nothing without a flow step.** No endpoint, table, control or option that no approved flow step needs.
5. **One heavy job at a time per machine** (`scripts/heavy`). Overloading a machine produces failures that look like bugs.
6. **Release first.** A delivery outranks a new build; a stuck story is parked after a bounded time, never allowed to block.
7. **Fix pipeline faults at once, without asking.** Ask the human only about money, paid accounts/vendors, contracts, legal
   text, physical devices, and exceptions to rules they set. Everything else: decide, record, continue.
8. **Be honest in reports.** Say what ran and what it asserted, what is not covered, and what is unverified. Never claim
   comprehensive coverage because a suite is green. Never promise a date without a measured rate.
9. **Nothing project- or machine-specific in the skill; no secrets anywhere in the repo.**

## The phases
Work through them in order; each ends with a gate you must pass before the next. Details are in `references/`.

| # | Phase | Output | Reference |
|---|---|---|---|
| 0 | **Orient**: is there a plan? a repo? a farm? read the brief if one exists | decision on which phases to run | this file |
| 1 | **Discovery brainstorm** with the human: vision, users, scope, compliance, stack, **deployment environments, accounts, budgets, machines, agent limits** | `factory-brief.md` with every mandatory item filled or explicitly waived; readiness gate green | `01-discovery-brainstorm.md` |
| 2 | **Research and plan** (skip if a reviewed plan exists): study reference software, reverse-engineer what is observable, build the feature inventory, map to epics/stories/slices, check mechanically, review independently | `research/` (raw sources + inventory), `plan/` (stories, dependency order), `plan-check` clean | `02-research-and-plan.md` |
| 3 | **Foundations**: repo, rules file, stack adapter, gates, hooks, CI + deploy guard, environments, `factory init`, `factory doctor` | a repo where `gate`, the critical run and a stub-agent dry run work | `04`, `05`, `11`, `12` |
| 4 | **Walking skeleton**: build ONE thin vertical slice through the whole lifecycle (flow, plan, tests, build, verify, release, smoke check) before scaling | a released slice; every adapter command proven | `03`, `06`, `12` |
| 5 | **Run**: queues into lanes, supervisor + janitor, the 30-minute health loop, release announcements | releases flowing, health green | `06`, `09` |
| 6 | **Operate and scale**: runbook, incidents, cost, parked stories, farm | stable throughput measured, not promised | `09`, `10`, `08` |

## Phase 0: orient (5 minutes)
- `ls` the project: a `.factory/` directory means the factory is installed (run `.factory/bin/factory health`). A `plan/` or
  similar means a plan exists: run `plan-check.py` on it before trusting it. A `factory-brief.md` means discovery was done.
- If installing: `scripts/factory init <repo>` copies the scripts into `<repo>/.factory/bin` (the project carries the exact
  version it runs) and writes `factory.conf` and the prompt templates. Then `.factory/bin/factory doctor`.
- Prove the install before trusting it: `scripts/selftest.sh` runs the whole pipeline on a toy project with a stub agent
  (about a minute, macOS and Linux). If that fails on this machine, fix that first.

## Phase 1: discovery (do not skip, do not shortcut)
Run the interview in `references/01-discovery-brainstorm.md`. The checklist there lists the **mandatory information**: if any
mandatory item is missing, the factory cannot be run safely (examples: where and how releases are deployed, who holds the
accounts and credentials, the machines available, the agent subscriptions and spend limits, the legal/regulatory constraints,
the acceptance owner, the alert channel). Collect them in one structured session, write `factory-brief.md` from
`templates/brief/factory-brief.md`, and stop for the human only on what the list marks as theirs to provide.

## Phase 2: research and plan
If the product has reference software (a competitor, an incumbent, an open-source analogue), the plan is built from evidence,
not from memory: `references/02-research-and-plan.md` gives the study protocol (public docs, trials, API/network
observation, open-source code reading, binary/app inspection where lawful), the evidence rules (raw sources immutable, every
claim cited, uncertainty flagged), the feature inventory with stable ids, the parity map, the story format, vertical
slicing, and the mechanical checks (`scripts/plan-check.py`, `scripts/queue.py`). Study to learn behaviour and requirements;
never copy source code, assets or text.

## Phase 3-4: foundations and the walking skeleton
Stack adapter (`factory.conf`): the gate, the critical run, stack up/down, deploy and post-release checks.
`references/11-adapting-to-stack.md` has the contract and worked examples. The first slice is built with the full lifecycle
(flow -> review -> plan -> review -> tests first -> build -> verify -> deliver -> release -> smoke check) so every adapter
command and every gate has been exercised by a real story before lanes multiply the cost of a mistake.

## Phase 5-6: run and operate
`factory start` launches the supervisor and janitor; lanes start from `queues/*.txt`. The coordinating agent runs
`factory health --fix` every 30 minutes (schedule it with whatever the host agent offers), acts on anything WARN/FAIL
immediately, and tells the human only when a release went out (what is new, where to click) or when something is broken that
could not be fixed. Reports are short, answer first. See `references/09-operations-runbook.md`.

## When something goes wrong
Search `references/08-failure-catalog.md` first: every entry has the symptom, the cause, the fix and the automatic guard.
If it is new: fix the cause, add a guard (script, check or prompt line), add a catalog entry, and tell the human in two lines.

## Files
- `scripts/` orchestration and tools (portable bash 3.2+/python3 stdlib; macOS and Linux). `scripts/factory help`.
- `templates/` factory.conf, prompts, document templates, CI workflow and deploy guard, agent permission settings, brief.
- `references/` the knowledge. `examples/` a worked walkthrough.
