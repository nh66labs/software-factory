<!-- sweep -->
You are building the next batch of epic {{EPIC}} of the {{PROJECT_NAME}} product, unattended: the stories of that epic not
yet built, in dependency order. Code repository: {{REPO}}. Stories: `grep -n '^### {{EPIC}}-' {{PLAN_DIR}}/**/*.md`.
1. Find what is already built: `git log {{INTEGRATION_BRANCH}} --oneline --grep '{{EPIC}}'`, the trace references in the code,
   and the existing code of the area. Never rebuild a built story.
2. Choose the next 6 to 10 unbuilt stories whose dependencies are already on `{{INTEGRATION_BRANCH}}` and that form a
   coherent, demoable piece of the business flow: backend, screens in every supported language, seed rows, and tests with
   independently computed values where money moves. Skip a story that needs something not built yet and say which and why
   in the commit message.
3. Map every story to its id in trace comments and in a commit line `Stories: <id>, <id>, ...` so progress can be counted.
If no story of this epic is buildable any more, change nothing and finish with `RESULT: BLOCKED deps <what is missing>`.
Then follow the build steps of build-story.md (worktree `{{STORY}}`, tests first, gate, rebase, commit, RESULT line).
