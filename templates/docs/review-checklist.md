# Independent review checklist (fill one per review; the reviewer did not write the work)
Reviewer: <session>   Subject: <flow | TIP | code | UX>   Version/commit: <...>

Completeness  [ ] every step/path/state present  [ ] acceptance criteria observable  [ ] nothing the story does not support
Correctness   [ ] rules match the domain pages / sources  [ ] figures have worked examples  [ ] dates/money/rounding explicit
Isolation     [ ] tenant boundary  [ ] permissions per role  [ ] input validation  [ ] no personal data in logs/errors
Tests         [ ] every step has a test in every layer it touches  [ ] expected values independent  [ ] fails on zero/empty
              [ ] both/all languages  [ ] nothing deleted/skipped/loosened vs base
Traceability  [ ] trace references both ways  [ ] no orphan endpoint/table/control
UX            [ ] states: default/disabled-with-reason/loading/error/empty  [ ] keyboard  [ ] accessibility  [ ] RTL
Process       [ ] writer != reviewer != approver  [ ] generated files regenerated, not hand-edited

Findings (severity: blocking | major | minor): <file:line or section - problem - fix>
Verdict: <no blocking findings | blocking findings listed above>      (the coordinator approves, not the reviewer)
