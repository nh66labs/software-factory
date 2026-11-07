# 02 - Research, reverse engineering and the plan

Goal: a plan a factory can build from without guessing, grounded in evidence about what the product must do. The plan is the
contract; later phases only add change requests to it. Do not start building from an unreviewed plan: the cost of a wrong
story is a lane of agent runs that build, test and release the wrong thing.

If a reviewed plan already exists, run `scripts/plan-check.py` on it and skip to phase 3.

## 2.1 Layout (target project)
```
research/
  raw/                IMMUTABLE evidence: saved pages, exported docs, screenshots, HAR files, API schemas, notes. Add only.
    <source>/<file>   with a sibling <file>.meta (url, date, how obtained, edition/version, licence/ToS note)
  sources.md          the source log: id, what, where, date, reliability (primary / vendor / community / inferred)
  reference/<product>/  one folder per studied product: capabilities, flows, screens, limits, pricing/plans, integrations
  domain/             product-neutral rules of the domain (tax, regulation, standards), each claim cited to a primary source
  inventory.md        the FEATURE INVENTORY: stable ids, one line each (see 2.4)
plan/
  epics/EP-<AREA>.md  stories (see templates/docs/story-section.md)
  slices.md           vertical slices (2.7)
  decisions.md        every product/technical decision with date, basis, who decided
  coverage.md         generated: feature -> stories, story -> features (parity check)
```
Pages in `reference/` and `domain/` describe facts only ("what X does", "what the law says"), with a citation for every claim.
Product requirements live in `plan/` and link to them. Never mix the two: it is how opinions get mistaken for facts.

## 2.2 Evidence rules
- Raw sources are never edited. A summary cites the raw file and the date. Contradictions are recorded, not silently resolved.
- Rank sources: primary (law, standard, official specification, the product's own documentation) > vendor material > community
  knowledge > inference. Domain rules quoted from a non-primary source are flagged `verify-with-primary` until checked.
- Every number that matters (rates, limits, thresholds, deadlines, field lengths) is quoted verbatim with its source.
- When you cannot observe something, write `unknown` and decide how to learn it; do not fill the gap with plausible text.
- Keep a **question list** for the human (owner-only items) and a **risk list** (what could invalidate the plan).

## 2.3 How to study reference software (in order of cost and lawfulness)
1. **Official documentation, help centres, knowledge bases, API references, changelogs, release notes, status pages, pricing
   and plan-comparison pages, onboarding emails, training videos' transcripts.** Many publish machine-readable indexes
   (sitemaps, `llms.txt`, OpenAPI documents). Fetch and store them raw. This alone usually yields 70% of the inventory.
2. **The product itself, as a user**: a trial or demo account the owner provides. Walk every menu, every create/edit/delete
   flow, every report, every setting; record screenshots, field lists, validation messages, empty/error states, keyboard
   behaviour, permission differences between roles, import/export formats, emails/documents it produces (save samples).
   Use browser automation to be systematic and repeatable; script the walk so it can be rerun when the product changes.
3. **Observed behaviour at the boundary**: the browser's network log (HAR) for the requests a feature makes (endpoints,
   payload shape, error codes, pagination), public/partner API schemas, webhook payloads, file formats it exports. This tells
   you the data model and rules the UI hides. Only on accounts you are entitled to use, within the terms of service.
4. **Community and ecosystem**: forums, issue trackers, feature-request boards, reviews (what users complain about is your
   differentiation list), third-party integrations and marketplaces (what the product is extended with).
5. **Open-source analogues**: read their data models, rules and test suites to learn edge cases. Respect licences; take
   ideas and edge cases, never code.
6. **App and binary inspection** (mobile apps, desktop clients, packaged web bundles) only where lawful and permitted
   (own device, no circumvention of protections, no licence violation): used to discover endpoints, feature flags,
   screens, supported formats and offline behaviour. Use whatever reverse-engineering tooling the host agent has; record
   method and findings in `research/raw`, not any extracted proprietary code or assets.

Legal and ethical guard rails (non-negotiable): respect terms of service and licences; no scraping behind authentication you
are not entitled to; no credential sharing; no circumvention of technical protections; no copying of source code, copy,
images or brand assets; personal data encountered is not stored. When unsure, ask the owner (legal text is owner-only).
Use a clean-room split: observers write **facts** into `research/`; a different step writes **our requirements** into
`plan/`, in our own words.

## 2.3a Never plan from a summary
Build the inventory from the RAW evidence: the markup/DOM (every element, attribute, tab, hidden panel, aria label, data
attribute, script behaviour), screenshots at phone and desktop width, and the network log. A model's summary of a page drops
structure (a third tab, a floating button, embedded video cards were all lost this way once). Mechanical string checks do not
see structure either. The independent plan review (2.9) is what catches it.

## 2.4 The feature inventory
`research/inventory.md` lists every capability of the reference product (and of the domain's mandatory rules), one per line:
```
- F-<AREA>-<nn> · <name> · source: <source id> [· plan: <edition/tier>] [· out-of-scope: <reason>]
```
Ids are stable forever; new features are appended. Mark features that do not apply (other jurisdictions, retired, enterprise-only
when out of scope) `out-of-scope` with the reason: a silent gap and a deliberate exclusion must be distinguishable. The inventory
is built area by area (menu by menu), and a second pass walks the product again looking only for what the inventory misses.

## 2.5 From inventory to plan
1. **Areas -> epics.** Group the inventory by product area; one epic per area, each with an owner module in the code (one crate/
   package/folder per area, so lanes seldom collide).
2. **Epics -> stories.** One story = one user flow a person can complete (create an invoice, approve a leave request, export a
   report). Template `templates/docs/story-section.md`: persona, `Depends on`, `Covers` (inventory ids), screens, a flow
   outline, alternate/error paths, **acceptance criteria that can be observed and tested** (AC1..), permissions, language
   notes. A story that cannot be tested from outside is not finished being written.
3. **Cross-cutting stories** are explicit and early: identity/tenancy/permissions, audit trail, numbering, localisation and
   formatting, notifications, import/export, background jobs, attachments, search, settings. Reference them from stories;
   never re-specify them.
4. **Dependencies are the order.** Priority labels from the reference vendor or analysts do NOT set build order; only
   `Depends on` does. Anything a story needs that is not built is a dependency, written down.
5. **Parity map.** `plan-check.py` fails when an in-scope inventory feature has no story, or a story covers an id that is not
   in the inventory. Run it after every plan edit.
6. **Out-of-scope is recorded** (with reason) in the inventory, never omitted.

## 2.6 Domain and regulatory knowledge
When money, tax, health, privacy or other regulated rules are involved, write `research/domain/<topic>.md` from primary
sources: the rule, the exact wording or number, the article/section, the date, and a worked example that tests can use as a
hand-computed expected value. These pages are what independent reviewers and test authors check against. Where only a
secondary source exists, flag it and put the verification on the owner's question list.

## 2.7 Vertical slices (so something real can be shown early)
Order work as **demoable business slices**, not architecture layers: each slice builds only the basics it needs and ends with
a working feature a real user can try end to end (create the thing, see it in a list, see its effect in a report). Basics are
never skipped or weakened; they are built just in time. The first slice is the walking skeleton (phase 4): the smallest
slice that exercises the whole pipeline (auth, one write path with money/data integrity, one report, deploy, smoke check).
`plan/slices.md` lists slices with the stories they contain and a demo script a human can follow.

## 2.8 UX and design inputs
Write the **UX principles** (what makes the product better than the reference for its users) and the **UI rules** (concrete
rules every screen follows: layout, states, language/RTL, keyboard, accessibility, copy tone) once; every UI story and every
UX review checks against them. Every time the owner corrects a UI mistake, fix it everywhere it applies and add the principle
to the rules (the principle, not the one-off fix). A prototype or design system, if the owner has one, is the reference for
control ids (`data-testid` = the control id) so tests and designs stay in step.

## 2.9 Reviewing the plan (independent, before freezing)
Run it headless with `templates/prompts/review-plan.md`, then apply it with a different author run (`plan-fix.md`) that verifies every
finding against the raw evidence and records what it applied and rejected. A fresh session that did not write the plan reviews: coverage (parity map), story sizing (one flow each), dependency sanity,
acceptance criteria testability, missing cross-cutting stories, regulatory claims vs sources, scope rule respected, and the
slice order. Findings are fixed; the coordinator records `Plan v1 approved (date)` in `plan/decisions.md`. After that the
plan changes only by change request (the story's section gets a new version; agents never invent behaviour).

## 2.10 Queues
`scripts/queue.py --plan plan --lanes N --out .factory/queues` orders by dependency, keeps an epic's stories in one lane
(fewer merge conflicts) and balances lanes. Stories already built are excluded with `--exclude-built`. Cross-lane
dependencies are handled by the driver (a story whose dependency is not yet merged is deferred and waits, bounded).
For epics too large to plan story by story up front, use batch ("sweep") ids `SWEEP-<EPIC>-<n>`: the run picks the next 6-10
buildable stories of the epic itself (template `templates/prompts/sweep.md`).

## 2.11 Output of this phase
`research/` (raw + logs + inventory + domain), `plan/` (epics, slices, decisions), `plan-check` clean, queues generated, the
owner's question list sent in one batch. Commit everything; the plan is part of the repository history.
