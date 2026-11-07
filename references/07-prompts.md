# 07 - Prompts for unattended runs

A headless run has one chance: it cannot ask, it cannot be nudged, and ending its turn ends the run. The prompts are the
contract. The templates are in `templates/prompts/`; `drive.sh` renders `{{PLACEHOLDERS}}` from the environment
(`render-prompt.py` reports any it could not fill, so a typo is visible).

## Structure of a build prompt
1. Identity and scope: ONE story, the repository, where the plan is, which documents to read (only what is needed).
2. Steps in order, each testable: check dependencies -> create/continue the worktree -> tests first -> build -> gates ->
   rebase -> commit -> stop.
3. The rules block (`_common.md`) appended to every run.
4. The result protocol: the final line is exactly `RESULT: DONE <short sha>` or `RESULT: BLOCKED <one-line reason>`;
   `BLOCKED deps <ids>` means "needs stories that are not built" (the driver defers, it is not a failure).

## Rules every run must carry (and why)
- **Never end the turn with work pending.** Run long commands in the foreground with a long timeout and repeat until done.
  A run that starts a background gate and writes "I'll check later" ends with no RESULT line and is retried from scratch.
- **Heavy commands wait their turn** (the lock); never start them in parallel or in the background.
- **Narrowest check first, full gate once.** Token cost matters: run the one spec that covers the change, the full gate when
  complete, and again only if code changed after it.
- **Never weaken a check**; independent expected values; unique ids for shared test resources; wipe-and-restart a polluted stack
  with the allowed commands.
- **Decide technical questions yourself**; stop only for owner-only matters.
- **Forbidden commands** (also denied by settings): destructive git forms, `--no-verify`, edits to rails files, other worktrees,
  other projects' containers, the production branch.
- Read narrowly, filter output, no sub-agents unless the owner allows (cost), keep context short.
- Commit message: what was built, deviations, a short self-review, and an honest list of what is NOT covered.

## Every command in a prompt must be runnable headlessly
Run each command class once under the real permission settings. A command on the ask list is a trap (the run reports BLOCKED
"needs approval"). When a wrapper's destructive form needs approval, the prompt names the allowed equivalent. Never tell a run
to do something it is not allowed to do.

## Prompt kinds
| Template | Used for |
|---|---|
| `build-story.md` | one story, end to end |
| `sweep.md` | the next 6-10 buildable stories of an epic (`SWEEP-<EPIC>-<n>` ids) |
| `fix-run.md` | resolve a rebase conflict or failing critical test in the story's worktree |
| `spec-flow.md` / `review-flow.md` | author / independent reviewer of a flow |
| `spec-tip.md` / `review-tip.md` | author / reviewer of the technical proposal |
| `tests-first.md` | the test author (a session that will not build the code) |
| `code-review.md` | independent review of a branch |
| custom `<STORY>.md` | a hand-written prompt for one special story (a larger effort is used) |

## Effort and model
`AGENT_EFFORT` for builds, `AGENT_FIX_EFFORT` for fix runs. Use a cheaper model for routine stories and a stronger one for
authoring plans, security-sensitive and money paths; record the policy in the brief. Measure with `factory usage`.

## Writing a good custom prompt
State the outcome in business terms with the numbers a test can check ("invoice 1,000.00 + 5% = 1,050.00; credit 400.00 + 20.00 =
420.00; balance 630.00"). List the stories it maps to. List the process rules that matter for THIS story only; the common block
carries the rest.
