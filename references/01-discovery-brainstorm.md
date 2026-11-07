# 01 - Discovery brainstorm (mandatory information)

Run this as one structured session with the human BEFORE any planning or building. Its output is `factory-brief.md`
(template: `templates/brief/factory-brief.md`). The factory refuses to start (`factory doctor` and the readiness gate below)
while a MANDATORY item is empty without an explicit waiver. The reason is cost: every missing item below has, in practice,
stalled a factory for hours or days when it surfaced late (no deploy target, no credentials, no alert channel, a machine too
small, an agent limit hit mid-night).

## How to run the session
1. Start with the vision in the human's words; do not lead with the checklist. Ask for examples, screenshots, links to the
   software they admire or must match.
2. Then walk the checklist section by section. For each item: ask, restate in one line, mark `got`, `waived (reason)` or
   `blocked (who, by when)`. Offer a recommended default for anything technical so the human can say "yes".
3. Decide what you can decide yourself (stack details, naming, structure) and record it in the decisions log; ask the human
   only for what the **owner-only list** names (below). Do not hand them a page-by-page approval chore: batch the questions.
4. Finish with a read-back: the one-page summary of scope, environments, constraints, and what you will do first.
5. Write the brief. Commit it. It is the source of truth for the readiness gate.

## Owner-only decisions (everything else you decide and record)
Money (budgets, paid plans, per-use costs), paid accounts and vendors, contracts and partners, legal text and regulatory
positions, pricing, physical devices, secrets handed over, exceptions to a rule the owner set, and acceptance of the product.

## Mandatory checklist
Legend: **M** mandatory (blocks the factory), **R** recommended (a waiver is recorded), **O** optional.

### A. Product and scope
| Item | Why it is needed | |
|---|---|---|
| Vision in one paragraph; who the users are (personas); the problem | scopes every story; reviewers check against it | M |
| Reference software to match or beat (names, versions, editions, regions) and whether parity is the goal | determines the research phase and the inventory | M |
| Scope rule: full parity in one release, or phased; what is explicitly out of scope (and why, e.g. other jurisdictions) | prevents both gold-plating and silent gaps | M |
| Platforms: web, mobile (iOS/Android), desktop, API, plugins; supported browsers/devices; offline needs | decides test matrix and stack | M |
| Languages and locales; right-to-left; number/date/currency formats; time zones | rework later is very expensive | M |
| Brand assets, design system or prototype, tone of copy | UI stories need a reference | R |
| Success measures and what "done" means for the whole product | the factory needs a stopping rule | M |
| Existing code, data, documents to import or integrate with | changes the first slice | R |

### B. Domain, compliance and risk
| Item | Why | |
|---|---|---|
| Regulated domain? (tax, finance, health, payments, children's data) and the authority/regulation names | the research must cite primary sources; legal text is owner-only | M |
| Data residency, retention, privacy regime (e.g. GDPR-like), audit-log requirements | architecture and tests | M |
| Security posture: auth method, roles/permissions model, tenant isolation, encryption, pen-test needs | prevents unsafe defaults | M |
| Money handling rules (rounding, currencies, tax inclusive/exclusive) if any money moves | hand-computed test values need the rules | M if money |
| Accessibility target (e.g. WCAG 2.2 AA) | a gate, not an afterthought | R |
| Third-party integrations (payments, e-invoicing, bank feeds, SMS, email, maps) and whether sandbox accounts exist | mocked locally, sandboxed on staging; accounts are owner-provided | M if any |

### C. Technology
| Item | Why | |
|---|---|---|
| Stack constraints or preferences (languages, frameworks, database, hosting style); otherwise the coordinator proposes and records a decision | the adapter and gates depend on it | M |
| Repository host, organisation, visibility, default branch names, branch protection capability | the integration/production model needs it | M |
| CI system and runners (hosted or self-hosted; where the deploy job runs) | the deploy guard lives there | M |
| Package registries, private dependencies, licences policy | builds fail without access | R |
| Observability: logs, metrics, error tracking, uptime checks | post-release checks and incident response | R |

### D. Environments and deployment (always asked; releases are meaningless without them)
| Item | Why | |
|---|---|---|
| Environment list: local per-story stacks, CI, **staging**, **production**, **demo**; which exist, which must be created | the branch model maps to them | M |
| For each deployed environment: provider/host, how it is reached (public URL, VPN/tailnet, SSH), OS, size | the deploy script needs a target | M |
| Domain names, DNS control, TLS certificates (who issues/renews) | blocked releases are usually DNS/TLS | M |
| Deploy mechanism (compose on a VM, Kubernetes, PaaS, serverless, app stores) and **who/what runs it** (CI runner label, SSH key, cloud role) | `release.sh` pushes; the deploy job must exist and be reachable | M |
| Database and storage for each environment: engine, size, backups, restore test, migration policy (forward-only?) | data safety | M |
| Secrets management: where secrets live, who rotates, how CI and the deploy job read them (never in the repo) | the biggest incident source | M |
| Rollback procedure and the smoke check that proves a release is healthy | `CMD_POST_RELEASE_CHECK` | M |
| Release policy: automatic after the critical pass, or human-approved; release windows; freeze periods | `AUTO_RELEASE` | M |
| Seed/demo data policy; whether production data may ever reach staging | test data rules | M |
| Email/SMS/webhook sinks for non-production (so tests never message real people) | safety | M if messaging |
| Cost ceiling for infrastructure per month | owner decision | M |

### E. The factory itself
| Item | Why | |
|---|---|---|
| Machines: how many, OS, CPU, RAM, disk, network, who administers them, remote access (SSH keys) | sizes lanes (`factory doctor`: ~1 stack per 3 cores and per N GB) | M |
| Agent CLIs and accounts: which agent(s), subscription or API, concurrency and **usage limits**, weekly caps, who renews | a limit hit at 3 a.m. stops everything | M |
| Spend policy: daily budget cap, alert threshold | `DAILY_BUDGET_USD` | M |
| Model/effort policy: which model for authoring, routine builds, fixes, reviews | cost vs quality | R |
| Alert channel: how the factory reaches the human (push, chat, email) and the quiet hours | `NOTIFY_CMD` | M |
| Permission to run unattended agents: the host environment may refuse headless runs in permissive mode; the human must grant an explicit rule, or choose another mode; test ONE headless run now | lanes cannot start without it | M |
| Coordinator cadence: health check every 30 minutes; reporting style (short, answer first) | operating contract | M |
| Time zone and working hours of the owner | when to expect answers; when decisions must be pre-made | R |
| Who accepts stories/slices and how (live demo URL, checklist) | acceptance is human | M |
| Rules the owner already has (e.g. "never run builds on the host", "Docker only", "no sub-agents") | become hard rules in the agents' rules file | M |

### F. Planning inputs
| Item | Why | |
|---|---|---|
| Is there an existing plan/backlog? where? format? | skip or reuse phase 2 | M |
| Research access: trial accounts/credentials for reference software, sample data, documents, API keys for studying (owner-provided, lawful) | research depends on it | M if studying live software |
| Priority labels from other sources are NOT build order; confirm dependency order is the rule | avoids rework | M |

## Readiness gate (all must be true to leave phase 1)
- Every **M** item is `got` or `waived (reason, by whom)`.
- Machines meet the capacity formula for the intended number of lanes (`factory doctor`).
- A deploy target and a way to reach it exist, or the human consciously chose "integration only for now" (`AUTO_RELEASE=0`).
- The alert channel works (send a test message).
- The brief is committed and the human has read the one-page summary.

## What to do when the human is unavailable
Never block the whole project: proceed on everything not depending on the missing item (research, plan, foundations, stories
that need no deployment), record the blocked items at the top of the brief with the date, and re-ask in the next summary.
