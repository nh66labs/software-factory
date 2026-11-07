# 03 - Story lifecycle and gates

Why gates exist: software written by agents drifts. Screens gain controls no flow needs, endpoints exist because they seemed
reasonable, the happy path works while the edit, error or second-language path is missing, and the journey across screens is
incomplete. Each piece is locally justified; the whole is incoherent. The gates make drift impossible to merge.

## The five rules behind the gates
1. One story = one user flow.
2. Flow before design, design before code. An unapproved flow or technical plan is never built from.
3. Independent review at every gate: writer, reviewer and approver are never the same agent/session.
4. Tests are written from the approved documents, before the code, by a session that will not build it.
5. Two-way traceability checked by a tool: every flow step is implemented and tested; every endpoint, table, control and job
   points back to the step that needs it. Anything unreferenced is rejected.

## Artefacts per story (names are conventions; keep them)
| Artefact | Path | Written by | Approved by |
|---|---|---|---|
| Story | `plan/epics/EP-*.md` | planning phase | coordinator (plan review) |
| User flow | `docs/flows/<ID>.md` | flow author | independent flow review, then coordinator |
| Technical implementation proposal (TIP) | `docs/tips/<ID>.md` | TIP author (from the approved flow only) | independent TIP review, then coordinator |
| Tests (failing first) | project test dirs + e2e | test author session | part of the build review |
| Implementation | code | builder session | code review + critical gate |
| Reviews | `docs/reviews/<ID>-{flow,tip,code,ux}.md` or the commit message | reviewers | - |
| Change requests | `docs/changes/<ID>-CR<n>.md` | whoever finds the gap | coordinator |
| Help/user article (each language) | `docs/help/...` | docs author | acceptance |

Approval is a single header line, machine-checked: `Status: Approved v<n> (<approver>, <YYYY-MM-DD>)`. The coordinator sets
it only after reading the independent review. The owner is asked only for the owner-only list (see 01).

Flow steps are numbered `S1, S2, ...`; alternate paths `A1` (steps `A1.1, A1.2`); error paths `E1 ...`. A full reference is
`ID/S3`, `ID/A2.1`, `ID/E4`. Code and tests carry `trace: ID/S3`.

## Statuses and gates
| # | Status | Work | Gate to leave |
|---|---|---|---|
| 1 | Ready | story in the plan with acceptance criteria and dependencies | Definition of Ready |
| 2 | Flow drafting | flow author writes the flow from the story + domain pages + UX rules | template complete; plan-check passes |
| 3 | Flow review | fresh session reviews with the checklist, fixes, reports | no blocking findings |
| 4 | Flow approval | coordinator reads review, sets `Approved v1` | approved |
| 5 | TIP drafting | TIP author works from the approved flow only | every step mapped to code and tests |
| 6 | TIP review | fresh session, checklist | no blocking findings |
| 7 | TIP approval | coordinator | approved |
| 8 | Tests first | different session writes the tests; they fail for the right reason | red, for the right reason |
| 9 | Build | builder implements until green, in the story's worktree | story tests + full gate green |
| 10 | Code review | fresh session reviews the diff | no open blocking finding |
| 11 | Delivery | rebase, critical tests on the rebased commit, merge, push, release | pass recorded; deploy guard satisfied |
| 12 | Acceptance | a session that did not build it runs the acceptance criteria on the integration stack; the owner accepts slices | accepted |
| 13 | Done | trace-check passes; Definition of Done holds | done |

For small, low-risk stories a lighter path is allowed and RECORDED in the decisions log: flow and TIP merged into one
document, review summary in the commit message, tests limited to real risks. The critical tests and the full gate are never
skipped.

## Definition of Ready
- Story has persona, dependencies, `Covers`, outline, acceptance criteria that can be observed.
- Stories it depends on are built (their code exists on the integration branch) or are being built with agreed interfaces.
- For UI stories: the reference screens/control ids exist.

## Definition of Done (all true)
1. Flow and TIP approved and match what was built; no open change request.
2. Every flow step (S, A, E) has an end-to-end test step and the unit tests the TIP lists, in every layer it touches.
3. All suites pass: unit/property, database (with isolation), API, component, end-to-end in every supported language and
   browser the project promises, accessibility.
4. Reverse traceability holds: every route, handler, migration, job, component and test id is annotated; `trace-check` clean.
5. Every visible string exists in every supported language; layout checked in right-to-left if supported.
6. Permissions: each role can/cannot do each step, tested at the API and in the UI.
7. Audit entries, notifications, postings and side effects listed in the flow are asserted.
8. UX review against the UX principles and UI rules passed.
9. Help article in every language; the parity map records the inventory ids as built.
10. Accepted.

## Change control
If the TIP author, a test author or a builder finds the approved flow wrong or incomplete, work stops and a **change request**
is raised on the story: the flow author updates the flow (new version), a fresh reviewer re-reviews, the coordinator re-approves,
then the TIP is updated and re-approved. Nobody resolves a gap by inventing behaviour in code. The same applies to the TIP:
a builder that needs an endpoint or table the TIP does not list raises a TIP change request. Cross-story changes (a shared
component owned by another story) go to the owning story's lane.

## Parallel work rules
- One story per agent session and one worktree per story; branch `story/<ID>`.
- Each code module/package/folder has an owning epic; a story outside that epic changes it only through a cross-story change.
- Migrations are numbered by timestamp and story so parallel branches do not collide; delivery renumbers on a clash.
- Generated files (API snapshots, clients, translation registries, coverage matrices) are regenerated or merged by tooling
  (`merge-json-keys.py` as a git merge driver for key-based JSON), never hand-merged.
- Stories merge through delivery one at a time, each proven on its rebased commit.
