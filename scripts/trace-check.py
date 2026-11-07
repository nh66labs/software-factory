#!/usr/bin/env python3
"""trace-check.py [--flows DIR] [--code DIR ...] [--story ID] [--marker trace]

Two-way traceability, mechanically:
  forward  every flow step (S1, A1, A1.2, E3 ...) of a story has at least one test that references it
  reverse  every `trace: <STORY>/<STEP>` reference points at a step that exists (no orphan code, no invented behaviour)
Flow documents are markdown with a heading per step:  `## S1 ...`, `### A2.1 ...`, `## E4 ...` under a file named <STORY>.md.
References are comments or test names containing `trace: STORY/STEP` (several allowed on one line, comma separated).
Exit 1 on any gap. Test files are recognised by `test`/`spec`/`e2e` in their path.
"""
import argparse
import glob
import os
import re

ap = argparse.ArgumentParser()
ap.add_argument("--flows", default="docs/flows")
ap.add_argument("--code", action="append", default=[])
ap.add_argument("--story")
ap.add_argument("--marker", default="trace")
args = ap.parse_args()
code_dirs = args.code or ["."]

steps = {}
for f in glob.glob(os.path.join(args.flows, "*.md")):
    sid = os.path.basename(f)[:-3]
    if args.story and sid != args.story:
        continue
    for line in open(f, encoding="utf-8"):
        m = re.match(r"^#{2,4}\s+([SAE]\d+(?:\.\d+)?)\b", line)
        if m:
            steps.setdefault(sid, set()).add(m.group(1))

ref_re = re.compile(re.escape(args.marker) + r":\s*([A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+)/([SAE]\d+(?:\.\d+)?)")
tests, code = set(), set()
skip = {".git", "node_modules", "target", "dist", "build", ".factory", "__pycache__", ".venv"}
for root_dir in code_dirs:
    for dirpath, dirs, files in os.walk(root_dir):
        dirs[:] = [d for d in dirs if d not in skip]
        for fn in files:
            if fn.endswith((".png", ".jpg", ".pdf", ".lock", ".svg", ".woff2")):
                continue
            path = os.path.join(dirpath, fn)
            try:
                text = open(path, encoding="utf-8", errors="ignore").read()
            except OSError:
                continue
            is_test = bool(re.search(r"(test|spec|e2e)", path, re.I))
            for sid, step in ref_re.findall(text):
                (tests if is_test else code).add((sid, step))

errors = []
for sid, st in sorted(steps.items()):
    for step in sorted(st):
        if (sid, step) not in tests:
            errors.append("%s/%s has no test referencing it" % (sid, step))
for sid, step in sorted(tests | code):
    if args.story and sid != args.story:
        continue
    if sid not in steps or step not in steps[sid]:
        errors.append("reference %s/%s points at a step that does not exist" % (sid, step))
print("trace-check: %d stories, %d steps, %d problem(s)" % (len(steps), sum(len(v) for v in steps.values()), len(errors)))
for e in errors:
    print("  - " + e)
raise SystemExit(1 if errors else 0)
