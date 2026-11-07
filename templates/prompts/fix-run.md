Story {{STORY}} is finished on branch {{BRANCH}} in the worktree {{WORKTREE}}, but delivering it stopped: either
`{{INTEGRATION_BRANCH}}` moved while it was built (another lane merged first), or the critical end-to-end tests failed on
the rebased result. The end of `{{MERGE_LOG}}` shows which and why: another story's change can have broken a test of this
one, or the other way round. Fix the CAUSE, in the code or in the old test; never weaken a test. Work ONLY in that worktree
(`cd` there; a `git rebase {{INTEGRATION_BRANCH}}` may be stopped half-way: check `git status`).

1. Finish the rebase onto `{{INTEGRATION_BRANCH}}`: for every conflict keep BOTH sides' intent. Generated files (API
   snapshots, generated clients, migration numbering, translation files, coverage matrices) are regenerated or merged by
   the project's tooling, never hand-picked. Renumber a migration if another story took the same number.
2. Re-verify what the merge could break: `{{CMD_GATE_FULL}}`, this story's own end-to-end specs, and the critical set. A
   crash or timeout is rerun ALONE before it is believed; record how often it happens.
3. Commit the fixes (a new commit if the rebase is complete). {{COMMIT_TRAILERS}}
   Do not merge or push. No sub-agents. Filter long output.

Do not stop to "check later": the delivery step runs the critical tests itself, but you must leave a state in which they
pass. Final line: `RESULT: DONE <short sha>` or `RESULT: BLOCKED <reason>`.
