# 05 - Testing, gates and the critical set

## 5.1 Principles
- **Flow steps are the unit of coverage.** Every step (S, A, E) has an end-to-end test step and the unit tests its plan lists;
  code-coverage percentages are a supporting measure, enforced as a ratchet (never lowered).
- **The backend is the source of truth.** Calculations (totals, tax, rounding, dates, balances, permissions) are proven at the
  domain layer with example and property tests; UI tests check that results are shown correctly.
- **Real infrastructure for your own parts.** Database tests run against the real engine with migrations and isolation rules;
  API tests run the real router. Only external services (payments, banks, messaging, OCR) are replaced by mocks/sandboxes.
- **Independent expected values.** For anything that computes money, quantities, dates or permissions, the expected value is
  written by hand from the specification. A test that reads its expectation from the screen or code under test proves nothing.
  Tests must also fail when a figure is zero or empty.
- **Every supported language, every promised browser/device.** Right-to-left runs also check that numbers, dates and codes are
  not reordered.
- **Never claim comprehensive coverage because the suite is green.** Reports say which scenarios ran and what they asserted,
  and list what is not covered (`templates/docs/test-report.md`, `coverage-matrix.md`).

## 5.2 Layers
Domain/unit + property tests; database (fresh DB per test, migrations, isolation per tenant, concurrency); API (permission
matrix, validation, idempotency, conflicts, pagination, error codes, schema diff); jobs/events (controllable clock);
documents (golden files); integrations (recorded contracts / mocks); frontend components (every state: default, disabled with
reason, loading, error, empty); end-to-end (the whole flow through the real UI against the real backend); accessibility
(automated checks + keyboard-only run); visual (baselines per screen/language/theme); performance budgets on heavy paths;
security (dependency audit, secret scan, dynamic scan baseline, permission fuzzing).

## 5.3 The gates
| Gate | When | Contains | Never contains |
|---|---|---|---|
| **fast** | pre-push hook | format, lint, unit tests of what changed, migration rules, plan/trace checks, fast typecheck | the end-to-end suite |
| **full** | builder before finishing; delivery's push gate | everything except end-to-end: all unit/db/api/component tests, generated-file checks, build, security scans, coverage ratchet | - |
| **critical** | delivery, on the rebased exact commit | the **critical set** in every promised language, fresh stack, **zero retries** | retries, skips |
| **matrix** | scheduled | every browser/device project, visual, performance, dynamic security | blocking each release |

The gate says SKIPPED only when what it checks does not exist yet, and says so; a missing tool is a FAIL. A gate that reports
"passed" for work it did not do is a defect.

## 5.4 The critical set
Tag the tests whose failure means "do not ship": money/data integrity paths, authentication and permissions, tenant isolation,
the core create-read-update-delete of each primary object, the reports that summarise them, and the deploy smoke. Hundreds, not
thousands: it runs on every delivery, alone on the machine, in a fresh stack, with **no retries**. A flaky critical test is a
defect in the test or the product, fixed the same day; it is never retried into a pass and never quietly removed from the set.
The verdict file is the only evidence (`scripts/verdict-from-*.py` produce it; `verdict-check.py` validates it): ok, at least
one pass (zero selected is a failure), zero failed, zero skipped, zero flaky, zero retries, commit equals the tested sha.

## 5.5 Test environment hygiene (each item cost hours once)
- **Isolation**: every stack has a unique name and port block (`FACTORY_STACK_NAME`, `FACTORY_PORT_BASE`), its own database,
  its own volumes; nothing shared except read-only caches.
- **Fresh data for the critical run** (`CMD_STACK_RESET`): leftover rows from earlier runs corrupt counts ("242 customers vs
  200 expected"). A wipe command must really wipe: test that the flag is honoured by the wrapper.
- **Shared resources need unique ids**: anything allocated by number (calendar days, ports, accounts, fixture ids) is checked
  for duplicates by a unit test that scans the suite, because two tests on one slot silently corrupt each other under parallelism.
- **Teardown always**: stop and wipe the stack when the run ends; leftover verification stacks exhaust memory and browsers then
  crash ("Target crashed"). Docker may leave an undeletable network behind; use a new stack name each run and skip stuck names.
- **Readiness waits sized for a loaded machine**: wait on events/conditions with generous ceilings (the default date appearing
  in a form took 5+ seconds under load); never fix a timing flake by deleting the assertion.
- **Test clock**: a controllable clock only in non-production environments, guarded so it cannot be enabled in production.
- **Mass failures mean the environment first**: when dozens of unrelated tests fail with crashes/timeouts/connection errors,
  suspect memory, disk, network or a leftover stack before the code (see failure catalog).

## 5.6 Flake policy
A failing test is rerun ALONE once, and the result recorded. Passing alone but failing in the suite = interaction or load: fix
the isolation/waits, do not retry. Passing alone and in the suite on rerun = unexplained flake: open a defect, keep the test,
and treat the next occurrence as a failure. Retries inside the critical run are forbidden by construction.

## 5.7 Coverage ratchet
Thresholds (lines, branches, functions, statements) per layer are written down once and may only go up. New screens/modules
come with behaviour tests for their error, empty, validation and cancel paths; excluding files from coverage or lowering a
threshold is forbidden. A scheduled sweep adds tests where a layer dips.

## 5.8 What reviewers check in tests
Expected values independent? Fails when the figure is zero? Covers the alternate and error paths, both languages, the role
matrix? Names carry the step reference? Nothing deleted, skipped or loosened relative to the base?

## 5.9 Rules the gate enforces mechanically (examples worth copying)
A branch that changes money/compute code must also change an end-to-end test (or carry `e2e-exempt: <reason>` in a commit
message); a story branch must name a story of the plan; every flow step of the story must have a test that runs; merged
migrations cannot be edited; generated files must be up to date; secrets scan clean; dependency advisories clean or listed
with an expiry date.
