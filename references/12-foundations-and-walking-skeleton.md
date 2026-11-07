# 12 - Foundations and the walking skeleton

Do not point lanes at an empty repository. Build the foundations and prove the pipeline with ONE thin slice first; every
mistake found here costs one story, not a night of parallel runs.

## 12.1 Foundations checklist (repository)
1. **Repository** with the integration and production branches, the plan and research folders, `.factory/` initialised
   (`factory init`), `.factory/state/` ignored.
2. **Rules file** for the agents (`templates/docs/project-rules.md` as CLAUDE.md/AGENTS.md): the non-negotiable rules, each
   with its enforcing check; commands table; directory map; how-to recipes. Keep it under ~150 lines; link to standards.
3. **Project wrapper** (`./run`, `make`, `just`, ...): up/down/reset/test/gate/e2e/generate; containerised or pinned toolchain.
4. **Gates**: fast (pre-push) and full; plan-check and trace-check wired in; coverage ratchet; secret scan; dependency audit
   with the exceptions file; generated-file freshness checks; migration rules.
5. **Test harness**: unit/db/api/component/e2e runners; fixtures that create isolated organisations/tenants per worker; a
   controllable clock (non-production only); the unique-resource scan; the verdict producer; the critical tag and the
   coverage-matrix check.
6. **i18n and RTL scaffolding** if the product is multilingual: key lint, completeness check, logical CSS lint, bidi helpers.
7. **Design system / UI rules**: a handful of components and the rules file; control ids as test ids.
8. **Hooks and permissions**: `install-hooks.sh` (human), agent settings with deny rules and the rails hook, trust accepted.
9. **CI and deploy**: workflow with the deploy guard, deploy script, rollback command, post-release smoke check, environments.
10. **Seed data**: a realistic shared sample dataset so figures in tests match what the owner sees in the demo.
11. **Observability**: structured logs without personal data, error tracking, uptime check, version endpoint (the smoke check uses it).
12. **`factory.conf`** filled; `factory doctor` clean; `scripts/selftest.sh` green on this machine; ONE real headless agent run succeeds
    here (proves permissions, trust and the adapter); a formatter ignore list covering guard-rail and generated files.

## 12.2 Choosing the walking skeleton
The smallest slice that touches every part of the pipeline for real:
- authentication and one role check; tenant isolation if multi-tenant
- ONE write path with data/money integrity (create a record that causes a computed effect)
- ONE read path summarising it (a list or report whose figure is asserted with a hand-computed value)
- in every supported language
- the migration, the API, the screen, the end-to-end test tagged critical
- deploy to the staging/production environment and a post-release smoke check
Example shapes: "create an order and see it in the order list and the sales total"; "post a payment and see the balance";
"submit a form and see the resulting document". Avoid architecture-only stories.

## 12.3 Run it by hand through the whole line
Flow -> review -> TIP -> review -> tests first -> build -> code review -> `factory deliver` -> release -> smoke check. Use the real
prompts and the real agent for the authoring and building steps (one lane, one story) so prompts, permissions and trust are
exercised. Record every surprise as a fix to the pipeline (and a catalog entry), not as a one-off.

## 12.4 Pipeline readiness checklist (all true before multiplying lanes)
- [ ] A headless build run finishes with a RESULT line, commits in its worktree, and nothing needed approval.
- [ ] A rebase conflict is repaired by a fix run (provoke one on purpose).
- [ ] A deliberately failing critical test blocks the delivery and is repaired by a fix run.
- [ ] `CMD_STACK_RESET` + `CMD_STACK_DOWN` leave nothing behind; two stacks run side by side.
- [ ] The critical run is fast enough on an idle machine to be run per delivery (record its duration; budget the serial time).
- [ ] Production cannot be moved by hand (try); the deploy refuses an untagged commit (try).
- [ ] The post-release check fails against a deliberately broken deploy.
- [ ] `factory health --fix` is green; the alert channel delivers a test message.
- [ ] Kill the network for two minutes during a run: the run is retried as INFRA, not failed.
- [ ] `PARK_AFTER_MIN` parks a story that cannot be fixed (use a tiny value to test), the lane continues.
- [ ] Cost per story is visible in `factory usage`; the daily cap pauses a lane (test with a tiny cap).

## 12.5 Scaling the queue
After the skeleton: generate queues (`queue.py`), start with as many lanes as `factory doctor` allows (usually 2), watch a day of
`health`, then add. Add an epic-level sweep lane for large, well-specified areas. Review parked stories every morning.
