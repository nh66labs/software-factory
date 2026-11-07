# 04 - Environments, delivery and the deploy guard

## 4.1 Branch and environment model
| Branch | Environment | Moves by | Proven by |
|---|---|---|---|
| `story/<ID>` | the story's isolated local stack | the builder's commits | story tests + full gate |
| `integration` (staging) | integration/staging stack, acceptance | `deliver.sh` fast-forward after the pass | critical tests on the exact commit, tag `e2e-critical/<sha>` |
| `production` (main) | production (and the demo, if separate) | `release.sh` fast-forward + push | the same tag; deploy job re-checks it |

- Single-environment projects set `PRODUCTION_BRANCH=INTEGRATION_BRANCH`: delivery still proves the commit before it lands.
- A **demo** environment that the owner watches is refreshed from the integration or production branch after each delivery
  (`CMD_DEMO_REFRESH`, run in the main checkout). Never run gates or end-to-end suites in the main checkout when its stack is
  the demo; verification uses its own worktrees and stack names.
- Rebase, never merge, branches onto the integration branch: history stays linear and each tag names one commit.

## 4.2 What the human must provision (collected in discovery, section D)
Repository + organisation, branch protection (or the hooks below), CI runner(s), deploy target(s) and how they are reached,
domain/DNS/TLS, secrets store, database and backups, third-party sandbox accounts, alert channel. The factory never invents
these; a missing one is a `blocked` item in the brief and `AUTO_RELEASE=0` until it exists.

## 4.3 Guard rails that make agents safe to run unattended
1. **Production moves only through `release.sh`.** A `reference-transaction` git hook (installed by `install-hooks.sh` into the
   shared git directory, outside every working tree, by the human) refuses any other move of the production branch, whichever
   command or tool attempts it. Agents are denied editing `.git/`, the hooks and the installer, so they cannot weaken the guard.
2. **Pre-push gate**: the fast gate runs before any push (`pre-push` hook), through the heavy lock.
3. **Agent permission settings** (`templates/agent-settings/claude-settings.example.json`), LEAST PRIVILEGE: headless runs use
   `acceptEdits` plus the project's allow list (the commands the prompts need, nothing more); deny rules for destructive and
   guard-bypassing forms (push, force, `--no-verify`, branch -f, reset/restore/clean, `git -C`, writes under `.git`, the rails
   files); a PreToolUse hook protecting the rails. A command on the **ask** list is a trap for a headless run: it cannot answer.
   The human approves this file once in phase 3; the coordinator never widens it on its own (hosts may refuse that as
   self-modification, rightly).
4. **Settings are passed explicitly** (`--settings`) because a project's settings are ignored, allow AND deny, in a folder whose
   trust dialog was never accepted; the worktrees folder is added (`--add-dir`) because agents may only edit inside allowed
   folders. `factory agent-smoke` proves all of it with one real run: worktree, edit, commit, the fast gate, a denied command
   refused, protected branches unmoved.
5. **Bypass mode is opt-in**, only on a dedicated machine/VM with nothing to lose, and some hosts refuse to launch it.
6. **Secrets**: never in the repository, prompts, logs or commit messages. CI/deploy read them from the platform's secret
   store. Agents get the minimum (a scoped token for the one repository). Test environments use sandbox credentials.
7. **No mutation of shared systems by tests**: non-production email/SMS/webhooks go to sinks; payment/bank integrations use
   sandboxes; destructive operations refuse to run against production by configuration.

## 4.4 The deploy guard (so only proven commits deploy)
`record-critical.sh` pushes an annotated tag `e2e-critical/<sha>` whose message records passed/failed counts, projects and
`retries: 0`. The deploy workflow (`templates/ci/deploy-workflow.yml`) runs `templates/ci/check-e2e-marker.sh` first:
it fetches the tag, checks it is annotated, points at exactly the deployed commit, records at least one pass and zero failures,
and otherwise stops the job with nothing changed. A manual `workflow_dispatch` input `allow_unverified` carries a reason that is
printed into the run: an owner decision, visible. This is a process guard, not a security boundary (whoever can push can push a
tag); it stops the mistake of deploying a commit nobody tested, which is the failure it exists for.

## 4.5 Release and post-release
`release.sh`: clean main checkout -> fetch -> production is an ancestor of integration -> pass recorded for the exact integration
head -> integration did not move meanwhile -> fast-forward production (env var set for the hook) -> push -> post-release check.
The **post-release check** (`CMD_POST_RELEASE_CHECK`) is a smoke test of the deployed system (login, one read, one write,
version endpoint equals the released sha). A green deploy workflow only proves the deploy script ran. A failed check logs
`POST-RELEASE-CHECK-FAILED`, alerts the owner, and the coordinator rolls back or fixes forward at once (decision recorded).

## 4.6 Rollback
Write the rollback procedure into the brief and make it one command (redeploy the previous tag/sha). Database migrations are
forward-only and backward-compatible for one release (expand/contract), so a code rollback never needs a data rollback.

## 4.7 Release communication (coordinator duty)
After every release: what is new (one line per user-visible change), where to click, the commit/deploy status, anything
unverified. Short, answer first. See `templates/docs/release-note.md`.

## 4.8 Scheduled checks that are not on the critical path
A periodic full browser/device matrix, a dependency-vulnerability audit with an exceptions list that carries expiry dates, a
visual regression run, and a performance budget run. They run on a schedule against the integration branch; failures become
fix work (a story or a ticket), they do not gate each release. A red scheduled check is treated like a stalled release: owned
and fixed the same day.
