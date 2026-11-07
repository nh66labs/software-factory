# software-factory

An agent skill that runs an **autonomous software factory**: from a product idea (discovery with the human, research and
reverse engineering of reference software, a dependency-ordered plan) to continuously tested, automatically released software,
built by unattended coding-agent runs that are scheduled, proven, supervised and repaired without a human in the loop.

It is the generalised, hardened form of a factory that built a large product for weeks; every failure it met is catalogued with
the guard that now prevents it (`references/08-failure-catalog.md`). Nothing in it is specific to a product, a stack or a
machine - the single adapter is a `factory.conf` per project.

## What is inside
| Path | |
|---|---|
| `SKILL.md` | the entry point for the agent: phases, hard rules, where everything is |
| `references/` | the knowledge: overview, discovery checklist (mandatory info), research/reverse-engineering/planning, story lifecycle, environments and deploy guard, testing and gates, orchestration, prompts, **failure catalog**, operations runbook, multi-machine, stack adapters, foundations + walking skeleton |
| `scripts/` | the orchestration: lane driver, delivery, critical-test proof, release, heavy lock, supervisor, janitor, health, doctor, remote verifier, hooks, plan/trace/queue tools, `selftest.sh` |
| `templates/` | `factory.conf`, prompts, flow/TIP/review/change-request/test-report templates, CI workflow + deploy guard, agent permission settings, the brief |
| `examples/` | a worked failure cascade, two example configs |

## Requirements
git, bash 3.2+ (macOS default is fine), python3 (standard library only), and for real runs an agent CLI (Claude Code by default;
adapters for Codex and any stdin agent). Docker only if your stack uses it. Works on macOS and Linux (Ubuntu tested).

## Install the skill
Claude Code: `git clone <this repo> ~/.claude/skills/software-factory` (or into a project's `.claude/skills/`). Other agents:
point the session at `SKILL.md` (`AGENTS.md` is a pointer). Then start a fresh session and say what you want, for example:

> Use the software-factory skill. I want to build <product>. Start with the discovery session.

## Prove it works on a machine (about 1-2 minutes)
`scripts/selftest.sh` builds a toy project with a stub agent and exercises two parallel lanes, a rebase conflict repaired by a
fix run, a failing critical test repaired by a fix run, the heavy lock with priority, the production-branch guard, the
deploy guard, story parking, and remote verification through a git remote. It must print `0 failed`.

## Use it in a project
```
scripts/factory init /path/to/project        # copies the scripts into <project>/.factory/bin, writes factory.conf + prompts
$EDITOR /path/to/project/.factory/factory.conf   # the stack adapter (references/11-adapting-to-stack.md)
/path/to/project/.factory/bin/factory doctor     # checks the machine, the config, sizes the parallelism
/path/to/project/.factory/bin/install-hooks.sh /path/to/project   # human operator: protects the production branch
/path/to/project/.factory/bin/factory queue lane-1 STORY-1 STORY-2   # or drop queues/*.txt
/path/to/project/.factory/bin/factory start      # supervisor + janitor; lanes start from queues
/path/to/project/.factory/bin/factory health --fix   # run every 30 minutes
```
The first real story should be a thin vertical slice delivered by hand through the whole line (phase 4) before lanes multiply.

## Design principles (why it is different from "run an agent in a loop")
Prove the exact commit before it moves; never weaken a check; independent writer/reviewer/approver; one heavy job at a time;
release before building; park instead of blocking; infrastructure faults are not story failures; processes are tracked by pid
file, never by name; every pipeline change is exercised before it is relied on; the human is asked only about money, accounts,
contracts, legal text, devices and acceptance.

## Status
Scripts are tested by `selftest.sh` on macOS and Ubuntu. The knowledge base reflects real incidents. See `references/10-multi-machine.md`
for scaling out and `references/08-failure-catalog.md` for what to expect.
