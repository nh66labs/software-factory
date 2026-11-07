# 11 - Adapting the factory to a stack (`factory.conf`)

The scripts know nothing about languages, frameworks or hosting. Everything stack-specific is a shell command in
`factory.conf`, run with `sh -c` inside the right directory with the **stack contract** in its environment:

| Variable | Meaning |
|---|---|
| `FACTORY_STORY` | story id, or `verify-<n>` for a verification slot |
| `FACTORY_WORKTREE` | the checkout the command runs in |
| `FACTORY_COMMIT` | the commit under test (verification only) |
| `FACTORY_STACK_NAME` | unique lowercase name, safe as a compose project / namespace / database prefix |
| `FACTORY_PORT_BASE` | first of 20 consecutive ports reserved for this stack (never hard-code ports) |

## The commands
| Setting | Contract | Failure meaning |
|---|---|---|
| `CMD_STACK_UP` | start this worktree's isolated stack (db, services, web) and wait until healthy | cannot test |
| `CMD_STACK_DOWN` | stop it AND wipe its data. **Test that the wipe really happens** (a wrapper once ignored the flag) | leaks volumes, pollutes later runs |
| `CMD_STACK_RESET` | wipe + start; used before the critical run | "the stack did not start" (exit 2) |
| `CMD_GATE_FAST` | seconds-to-minutes: format, lint, typecheck, unit tests of what changed, plan/trace/migration checks | blocks push |
| `CMD_GATE_FULL` | all non-end-to-end checks: every unit/db/api/component test, generated-file freshness, build, scans, coverage ratchet | blocks delivery |
| `CMD_E2E_TARGETED` | run a few specs; args appended | optional, for fix runs |
| `CMD_E2E_CRITICAL` | run the critical set of the commit in `$1`, **zero retries**, write the verdict to `E2E_VERDICT_FILE` (JSON: commit, ok, passed, failed, retries, reasons) | blocks delivery |
| `CMD_DEMO_REFRESH` | in the MAIN checkout: rebuild the demo from the integration branch | non-fatal |
| `CMD_POST_RELEASE_CHECK` | smoke test of production; exit 0 = healthy; version endpoint equals the released sha | alerts, release marked suspect |
| `CMD_DEPLOY_STATUS` | print the last deploy's state; exit 0 = healthy | health WARN/FAIL |
| `CMD_STORY_EXISTS` | exit 0 if story `$FACTORY_STORY` exists (default: grep the plan) | the id is rejected before any run |
| `CMD_CACHE_TRIM` | trim build caches; **must be safe while builds run** | disk fills |

Make the project's own wrapper (a `./run`, `make`, `just` or `./dev` script) the single entry point, and have `factory.conf` call
it. Everything runs in containers or a pinned toolchain; the host needs only git and the container engine.

## Verdict producers (`scripts/verdict-from-*.py`)
- Playwright: `npx playwright test --grep @critical --retries=0 --reporter=json > report.json; verdict-from-playwright.py report.json "$1" verdict.json`
- JUnit XML (pytest `--junitxml`, go-junit-report, Gradle, Cypress junit reporter): `verdict-from-junit.py report.xml "$1" verdict.json`
- Anything else: write the JSON yourself; `verdict-check.py` validates it (ok, passed>=1, failed=0, skipped=0, flaky=0, retries=0, commit matches).

## Worked examples (adapt the names)
**Web app, Node/TypeScript, Docker Compose, Playwright**
```
STACK_ENGINE=docker
CMD_STACK_UP='docker compose -p "$FACTORY_STACK_NAME" up -d --wait'
CMD_STACK_DOWN='docker compose -p "$FACTORY_STACK_NAME" down -v --remove-orphans'
CMD_STACK_RESET='docker compose -p "$FACTORY_STACK_NAME" down -v --remove-orphans && docker compose -p "$FACTORY_STACK_NAME" up -d --wait && ./scripts/migrate-and-seed'
CMD_GATE_FAST='./run lint && ./run typecheck && ./run test --changed'
CMD_GATE_FULL='./run lint && ./run typecheck && ./run test --coverage && ./run build && ./run audit'
CMD_E2E_CRITICAL='./run e2e --grep @critical --retries=0 --reporter=json > e2e/report.json; python3 -I .factory/bin/verdict-from-playwright.py e2e/report.json "$1" e2e/critical-result.json'
E2E_VERDICT_FILE=e2e/critical-result.json
```
Compose file: take ports from `${FACTORY_PORT_BASE}` + offsets; name volumes per project; mount a shared READ-ONLY dependency cache.

**Python service, pytest**
```
CMD_GATE_FULL='ruff check . && mypy . && pytest -q --cov --cov-fail-under=85'
CMD_E2E_CRITICAL='pytest -m critical -p no:randomly --maxfail=0 --junitxml=report.xml; python3 -I .factory/bin/verdict-from-junit.py report.xml "$1" critical-result.json'
```
**Rust workspace**: `cargo fmt --check && cargo clippy -D warnings && cargo nextest run`; mount a persistent build-output volume
shared by story worktrees (cold compiles are slow) and trim it with `CMD_CACHE_TRIM` (incremental data and files untouched for a
day) because it grows without bound.
**Go**: `golangci-lint run && go test ./... -race`; E2E with the project's integration binary; JUnit via `gotestsum`.
**Rails/Django**: gate = linters + test suite; stack = compose with the app, database and a headless browser; seed script.
**Mobile**: gate on the shared logic and web layer; device/emulator suites run in the scheduled matrix on machines that have
them; the critical set uses the web/emulator layer. Store releases are owner/vendor-gated: `AUTO_RELEASE=0` for those targets.
**Static site / library**: single environment, `PRODUCTION_BRANCH=INTEGRATION_BRANCH`, critical set = build + link check + a
smoke render; release = publish step in CI behind the same tag guard.

## Rails and settings for the agent (see `templates/agent-settings/`)
Allow the commands the prompts use; deny destructive and guard-bypassing forms; PreToolUse hook protecting hooks/settings/
workflows/migrations already merged; no command the prompts rely on may be on the ask list.

## Checklist when adapting
1. `CMD_STACK_RESET` followed by `CMD_STACK_DOWN` leaves nothing behind (list containers/volumes/ports afterwards).
2. Two stacks with different `FACTORY_STACK_NAME` run side by side without port or data collisions.
3. The fast gate is quick (< 2 min typical) and the full gate completes headless with no prompts.
4. The critical command fails (exit and verdict) when you break a critical test on purpose, and fails when zero tests match.
5. The post-release check fails against a broken deploy.
6. `factory doctor` is clean; `scripts/selftest.sh` passes; one walking-skeleton story delivers and releases.
