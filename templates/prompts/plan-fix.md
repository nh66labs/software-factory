You are the PLAN AUTHOR's delegate for the {{PROJECT_NAME}} product. An independent reviewer wrote docs/reviews/plan-review.md.
Apply its findings to the plan, using the raw evidence in the research folder as the only source of truth for what the
reference does (verify every claim of the review against the raw files before changing anything; if the review is wrong, say so).
- Fix every blocking and major finding in {{PLAN_DIR}} (epics, slices, decisions), research/inventory.md and factory-brief.md:
  exact expected values in acceptance criteria, missing behaviours, dependency edges, decisions for open questions you can decide
  (record them in {{PLAN_DIR}}/decisions.md with the basis), owner questions added to the brief's blocked list.
- Where an already DELIVERED story is affected, do not edit code: write a change request docs/changes/<STORY>-CR<n>.md (problem,
  evidence, change, impact) and add the change to the acceptance criteria of the story that will carry it.
- Keep story ids stable; add new stories at the end of their epic with new ids; keep the plan format (### <ID> · <title>, fields).
- Run nothing that changes code. When done, write a short changelog at the end of docs/reviews/plan-review.md ("Applied: ...",
  "Rejected: ... because ...").
Do not commit. Your final message ends with one line: RESULT: DONE <n findings applied>   or   RESULT: BLOCKED <reason>.
