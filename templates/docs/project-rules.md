# <Project> - rules for every agent (this is the repository's CLAUDE.md / AGENTS.md; keep it short and enforced by tools)

## The plan
The plan lives at <path>; it is read-only from this repository. A story `<ID>` is the section `### <ID> · ...` of
`plan/epics/EP-<AREA>.md`. Per story here: `docs/flows/<ID>.md`, `docs/tips/<ID>.md`, `docs/reviews/<ID>-*.md`,
`docs/changes/<ID>-CR<n>.md`, `docs/help/...`.

## Non-negotiable rules (each one is checked by a tool or a hook; say how)
1. **Never build from an unapproved flow or TIP.** Approved = the header line exactly `Status: Approved v<n> (<approver>, <date>)`
   set by the coordinator after an independent review (plan-check rejects any other form).
2. **Nothing without a flow step.** No control, endpoint, column, table, job or option the approved TIP does not list. Raise a
   change request instead of inventing behaviour.
3. **Tests first, by a different session than the one that builds.** They must fail for the right reason first.
4. **Never delete, skip or weaken a test** (or accept a contradicting snapshot, lower a threshold, exclude from coverage).
5. **Traceability**: `trace: <ID>/<step>` on handlers, services, jobs, migrations, components, tests; trace-check enforces it.
6. **<Domain invariants>**: e.g. all computation in the backend; money is never a float; tenant data only inside the tenant
   transaction with isolation enforced by the database; every handler checks its permission key first; every visible string in
   every supported language; logical CSS only; generated clients only. (Write YOUR invariants here, with the enforcing check.)
7. **Everything runs through the project wrapper `<./run>`**, never ad-hoc host tooling. Never edit a merged migration.
8. **The production branch moves only through the release script.** Never edit hooks, agent settings, CI workflows or `.git`.
   Push only your branch with an explicit refspec. No `--no-verify`, no force push, no merging by an agent.
9. **Financial/critical logic needs end-to-end tests with independently computed expected values** that fail on zero/empty.
   Never claim comprehensive coverage because the suite is green: state what ran, what it asserted, what is not covered.

## Commands (the wrapper's table: up/down/reset, test, e2e, gate --fast/--full, generate, demo)

## Where things live (directory map with the owning epic of each module)

## How to (add a migration / endpoint / screen / test) - three short recipes with the exact commands

## When a rule is broken or corrected
Update this file (or the standard it links) in the same change so it cannot recur. UI corrections become rules in the UI rules
(the principle, not the one-off fix).
