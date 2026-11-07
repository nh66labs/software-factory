#!/usr/bin/env python3
"""verdict-check.py <verdict.json> <commit> <runner-exit-code>

The verdict file is the only evidence of a critical run; the runner's exit code alone is never trusted.
Required: {"commit": "<sha>", "ok": true, "passed": N>=1, "failed": 0, "retries": 0}; optional "reasons": [..],
"skipped": N (must be 0), "flaky": N (must be 0).
Exit 0 pass; 1 fail (reasons printed on stderr); 2 unreadable.
"""
import json
import sys

path, commit, code = sys.argv[1], sys.argv[2], int(sys.argv[3] or 0)
try:
    v = json.load(open(path))
except Exception as exc:  # noqa: BLE001
    print("critical-e2e: unreadable verdict %s: %s" % (path, exc), file=sys.stderr)
    sys.exit(2)
reasons = list(v.get("reasons") or [])
if code != 0:
    reasons.append("the test runner exited with %d" % code)
if v.get("ok") is not True:
    reasons.append("verdict ok is not true")
if int(v.get("passed") or 0) < 1:
    reasons.append("no critical test passed (zero tests selected is a failure)")
for key in ("failed", "retries", "skipped", "flaky"):
    if int(v.get(key) or 0) != 0:
        reasons.append("%s=%s (must be 0)" % (key, v.get(key)))
if v.get("commit") != commit:
    reasons.append("the verdict is for another commit (%s)" % v.get("commit"))
if reasons:
    print("critical-e2e: FAILED. Verdict: %s" % path, file=sys.stderr)
    for r in reasons:
        print("  - %s" % r, file=sys.stderr)
    sys.exit(1)
print("critical-e2e: %s critical test run(s) passed on %s, none retried" % (v.get("passed"), commit))
