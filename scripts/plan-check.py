#!/usr/bin/env python3
"""plan-check.py [--plan DIR] [--inventory FILE] [--map-field "Covers"]

Mechanical checks of a plan before any agent builds from it. A plan that fails these produces drift later (stories no
flow needs, features nobody builds, circular waits that only show up as DEFERRED forever).

Plan format (see templates/docs/story-section.md): epics are markdown files; every story is a section
    ### <STORY-ID> · <title>
with field lines:
    - Depends on: ID, ID          (stories that must be built first)
    - Covers: FEATURE-ID, ...     (entries of the feature inventory it implements)
    - Acceptance:                 (followed by a list; each item starts with ACn)
The feature inventory (research/inventory.md) lists one feature per line:   - <FEATURE-ID> · <name> [· out-of-scope: <why>]

Checks: unique ids; every dependency exists; no dependency cycle; every story has acceptance criteria; every in-scope
inventory feature is covered by at least one story; every Covers id exists in the inventory. Exit 1 on any problem.
"""
import argparse
import glob
import os
import re
import sys

ap = argparse.ArgumentParser()
ap.add_argument("--plan", default="plan")
ap.add_argument("--inventory", default="research/inventory.md")
args = ap.parse_args()

HEAD = re.compile(r"^#{2,4}\s+([A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+)\s*[·\-:–]\s*(.+)$")
stories = {}
errors = []
for path in sorted(glob.glob(os.path.join(args.plan, "**", "*.md"), recursive=True)):
    cur = None
    mode = None
    for line in open(path, encoding="utf-8"):
        m = HEAD.match(line.rstrip())
        if m:
            cur = m.group(1)
            if cur in stories:
                errors.append("duplicate story id %s (%s and %s)" % (cur, stories[cur]["file"], path))
            stories[cur] = {"file": path, "title": m.group(2), "deps": [], "covers": [], "ac": 0}
            mode = None
            continue
        if cur is None:
            continue
        s = stories[cur]
        low = line.strip().lower()
        if low.startswith("- depends on:"):
            s["deps"] = [x.strip() for x in line.split(":", 1)[1].split(",") if x.strip() and x.strip().lower() not in ("none", "-", "nothing")]
            mode = None
        elif low.startswith("- covers:"):
            s["covers"] = [x.strip() for x in line.split(":", 1)[1].split(",") if x.strip()]
            mode = None
        elif low.startswith("- acceptance:"):
            mode = "ac"
        elif mode == "ac" and re.match(r"^\s+[-*]\s*(AC\d+|\d+[.)])", line, re.I):
            s["ac"] += 1
        elif line.startswith("- ") and not line.startswith("  "):
            mode = None

if not stories:
    print("plan-check: no stories found under %s" % args.plan)
    sys.exit(1)
for sid, s in stories.items():
    for d in s["deps"]:
        if d not in stories:
            errors.append("%s depends on unknown story %s" % (sid, d))
    if s["ac"] == 0:
        errors.append("%s has no acceptance criteria" % sid)

# cycles
state = {}
def visit(n, trail):
    state[n] = 1
    for d in stories[n]["deps"]:
        if d not in stories:
            continue
        if state.get(d) == 1:
            errors.append("dependency cycle: %s" % " -> ".join(trail + [n, d]))
        elif d not in state:
            visit(d, trail + [n])
    state[n] = 2
for n in stories:
    if n not in state:
        visit(n, [])

# feature coverage
inv = {}
if os.path.isfile(args.inventory):
    for line in open(args.inventory, encoding="utf-8"):
        m = re.match(r"^\s*[-*|]\s*`?([A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+)`?\s*[·|\-:–]\s*(.*)$", line)
        if m:
            inv[m.group(1)] = "out-of-scope" in line.lower()
    covered = set(f for s in stories.values() for f in s["covers"])
    for f, out in inv.items():
        if not out and f not in covered:
            errors.append("inventory feature %s is not covered by any story" % f)
    for sid, s in stories.items():
        for f in s["covers"]:
            if f not in inv:
                errors.append("%s covers %s which is not in the inventory" % (sid, f))
else:
    print("plan-check: no inventory at %s (feature coverage not checked)" % args.inventory)

print("plan-check: %d stories, %d inventory features, %d problem(s)" % (len(stories), len(inv), len(errors)))
for e in errors:
    print("  - " + e)
sys.exit(1 if errors else 0)
