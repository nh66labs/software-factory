# 13 - Right-sizing: how much process a project needs

The full lifecycle is for products with money, data, permissions and many people relying on them. A small project run with the
whole ceremony wastes tokens and time; a large one run lean ships drift. Choose a tier in discovery, record it as a decision, and
revisit it when the project grows. What NEVER shrinks, at any tier: the plan from raw evidence with an independent review, tests
written from acceptance criteria with independent expected values, the critical run on the exact commit before it moves, the
deploy guard, least-privilege agents, and the health loop.

| | **Micro** | **Small** | **Standard** | **Large** |
|---|---|---|---|---|
| Example | a landing page, a script, a single-page site | a marketing site, an internal tool, a small API | a SaaS module, an app with accounts and data | a full product, money/regulated domain |
| Stories | 1-5 | 5-25 | 25-200 | 200+ |
| Discovery | the mandatory items only, 15 minutes | full checklist | full checklist | full checklist + owner workshop |
| Research | raw evidence + inventory | + reference notes | + domain pages | + primary sources for every rule |
| Plan review | one independent review | one review + fix pass | review per epic | review per epic + domain reviewer |
| Flow + TIP docs | none: story AC are the spec | none: story AC + a short note in the commit | flow + TIP per story, reviewed | flow + TIP, reviewed, change requests |
| Tests first by another session | no (same run writes tests first) | no | yes | yes |
| Code review | the critical run + gate | + a review run per slice | per story | per story + protected-area reviewer |
| Lanes | 1 | 1-2 | per capacity | per capacity, several machines |
| Critical set | the whole e2e suite (small) | tagged subset | tagged subset | tagged subset + scheduled matrix |
| Verifier | local | local | local or remote | remote |
| Release | automatic after the pass | automatic | automatic (or owner-approved) | owner policy |

## Signals to move up a tier
Money moves; personal data is stored; more than one role; external integrations; more than one lane conflicts often; a defect
escaped to production; the owner cannot follow progress from the demo alone.

## Signals you over-sized
Agents spend more tokens on documents than on code and tests; reviews find nothing for several stories in a row; the owner asks
why a trivial change took a day.
