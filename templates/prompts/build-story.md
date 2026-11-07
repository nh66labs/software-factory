You are building ONE story of the {{PROJECT_NAME}} product end to end, unattended. Story: {{STORY}}.
Code repository (main checkout): {{REPO}}. The plan (read-only): {{PLAN_DIR}}. Find the story with
`grep -rn '^### {{STORY}}' {{PLAN_DIR}}` and read its flow and technical plan if the repository has them
(docs/flows/{{STORY}}.md, docs/tips/{{STORY}}.md). Read the repository's rules file first, only the parts you need.

Steps
0. Check that every story this one depends on is already on `{{INTEGRATION_BRANCH}}` (its code exists). If one is missing,
   stop at once without creating anything: `RESULT: BLOCKED deps <missing story ids>`.
1. From the main checkout: `git worktree add {{WORKTREE}} -b {{BRANCH}} {{INTEGRATION_BRANCH}}` and work only there. If it already exists (an earlier run was interrupted), continue
   in it: check what is written, finish it, re-run the checks; do not start over.
2. Tests first, from the flow's steps: only tests that guard real risk (security, money, data isolation, concurrency,
   accessibility, every supported language), each carrying its trace reference. They must fail for the right reason first.
3. Build. Everything through the project's own commands (never ad-hoc host tooling). Regenerate generated files, never
   hand-edit them.
4. `{{CMD_GATE_FULL}}` must pass, then the story's end-to-end specs and the critical set. Fix failures; never weaken a
   test, raise a timeout to hide a defect, skip a test, or lower a threshold to make a check pass.
5. Before the final checks run `git rebase {{INTEGRATION_BRANCH}}` (other lanes merge in parallel) and regenerate generated
   files; then run the final checks on the rebased code.
6. Commit on the branch: what was built, deviations from the plan, a short self-review (defects found and fixed), and an
   honest list of what is NOT covered. {{COMMIT_TRAILERS}}
7. Stop there. Do not merge or push the integration or production branch: the driver delivers.

Your final message ends with one line: `RESULT: DONE <short sha>` or `RESULT: BLOCKED <one-line reason>`.
