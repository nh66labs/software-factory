
## Rules for every unattended run (appended to your task)
- **Never end your turn while work is pending.** Ending a turn ends the whole run; a run without the final `RESULT:` line
  is a failure that is retried from scratch. Run gates, test suites and every long command in the FOREGROUND with a long
  timeout and repeat the call until it finishes. Never start a command in the background and stop to "check later".
- **Heavy commands wait their turn.** The gate and the end-to-end suites take a machine-wide lock; only one runs at a time.
  Just run them; if they print "heavy: waiting for the machine" they continue by themselves. Never start them in parallel.
- **Narrowest check while building, full gate once when done.** Run the one test file or spec that covers your change;
  run the full gate when the code is complete and again only if code changed after it. Do not rerun a green suite.
- **Never weaken a check.** Do not delete, skip or loosen a test, accept a contradicting snapshot, lower a coverage
  threshold, exclude a file from coverage or add an exception to make something pass. Fix the cause. If a test is
  genuinely wrong, say why in the commit message and fix the test to assert the correct value, computed independently.
- **Expected values are computed independently.** For anything that computes money, quantities, dates or permissions,
  write the expected value by hand from the specification, never by reading it back from the screen or code under test.
- **Shared resources need unique ids.** Any test resource that is allocated by number (calendar days, ports, accounts,
  fixtures) must be unique across the whole suite; before taking one, list the ones in use.
- **A polluted test database** (extra rows from earlier runs, wrong counts) is cured by wiping and restarting your own
  stack with the project's stack commands, then rerunning the failing tests. Never report BLOCKED for that.
- **Do not wait for permission.** Decide technical questions yourself and record deviations in the commit message. Stop
  only for matters reserved to the owner: money, paid accounts or vendors, contracts, legal text, physical devices, or an
  exception to a rule the owner set.
- **Forbidden:** `git -C`, `git reset`, `git checkout`, `git restore`, `git clean`, `git worktree remove`, force pushes,
  `--no-verify`, editing hooks / agent settings / CI workflows / anything under `.git`, touching other worktrees,
  other projects' containers, or the production branch. {{PROTECT_PATHS_NOTE}}
- Read only what you need; never print a whole file or log (grep first, `tail -40`). One run, one thread: no sub-agents.
- Keep your context short: if a long investigation is needed, write findings into the commit message or a note file in the
  worktree, not into chat.
