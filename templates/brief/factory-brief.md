# Factory brief - <product name>
Status: <draft | READY (date, by whom)>        Readiness gate: <all M items got or waived>

## 0. One-page summary (read back to the owner)
Vision: ... | Users: ... | Scope rule: ... | First slice: ... | Environments: ... | Machines: ... | Agent budget: ... | Alerts: ...

## 1. Product and scope                              (got / waived / blocked-by)
- Vision / personas / problem:
- Reference software (name, edition, region) and goal (parity / differentiate):
- Scope rule (full parity in one release | phased) and explicit out-of-scope list with reasons:
- Platforms and supported browsers/devices; offline needs:
- Languages/locales, RTL, formats, time zones:
- Brand/design assets or prototype:
- Success measures / what "done" means for the whole product:
- Existing code/data/documents to import or integrate:

## 2. Domain, compliance, risk
- Regulated domain, authorities, primary sources to cite:
- Data residency / retention / privacy / audit requirements:
- Security posture (auth, roles, tenant isolation, encryption, pen-test):
- Money rules (rounding, currencies, tax inclusive/exclusive):
- Accessibility target:
- Third-party integrations and sandbox accounts (who provides):

## 3. Technology
- Stack constraints/preferences (or "coordinator proposes"; decision id):
- Repository host/org/visibility/default branches/branch protection:
- CI system and runners:
- Package registries / private dependencies / licence policy:
- Observability (logs, metrics, errors, uptime):

## 4. Environments and deployment (mandatory)
| Env | Exists? | Provider/host | Reached how | OS/size | URL/domain | TLS owner | Deploy mechanism + runner | DB/storage/backups | Secrets store |
|---|---|---|---|---|---|---|---|---|---|
| local per-story | | | | | | | | | |
| CI | | | | | | | | | |
| staging/integration | | | | | | | | | |
| production | | | | | | | | | |
| demo (watched by owner) | | | | | | | | | |
- Rollback procedure (one command) and post-release smoke check:
- Release policy (automatic after pass | owner-approved), windows, freezes:
- Seed/demo data policy; production data never reaches staging? 
- Non-production messaging sinks (email/SMS/webhook):
- Monthly infrastructure cost ceiling:

## 5. The factory
- Machines (count, OS, CPU, RAM, disk, network, admin, SSH access):
- Agent CLIs and accounts, subscription/API, concurrency, usage limits, renewal owner:
- Daily budget cap and alert threshold:
- Model/effort policy (author / routine build / fix / review):
- Alert channel (how the factory reaches the owner) and quiet hours; test message sent: <yes/no>
- Coordinator cadence: health check every 30 min; report style (short, answer first)
- Owner time zone / availability:
- Acceptance: who accepts, how (demo URL, checklist):
- Standing rules from the owner (e.g. Docker-only, no sub-agents, language of docs):

## 6. Planning inputs
- Existing plan/backlog (where, format):
- Research access (trial accounts, sample data, API keys - owner-provided, lawful):
- Build order rule: dependencies only (priority labels do not set order): <confirmed>

## 7. Decisions made by the coordinator during discovery (id, date, decision, basis)

## 8. Blocked items (owner, needed by)
