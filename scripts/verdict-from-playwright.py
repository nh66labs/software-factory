#!/usr/bin/env python3
"""verdict-from-playwright.py <playwright-json-report> <commit> <verdict-out.json>

Turns Playwright's JSON reporter output (`--reporter=json`) into the factory's verdict file. Strict by design:
  passed = expected; failed = unexpected; flaky (passed only on a retry) and skipped both make the verdict not ok;
  retries > 0 anywhere makes it not ok. Zero passed tests is not ok. Run the critical set with `--retries=0`.
"""
import json
import sys

report_path, commit, out_path = sys.argv[1:4]
report = json.load(open(report_path))
stats = report.get("stats") or {}
passed = int(stats.get("expected", 0))
failed = int(stats.get("unexpected", 0))
flaky = int(stats.get("flaky", 0))
skipped = int(stats.get("skipped", 0))
retries = 0
reasons = []


def walk(suite, trail=""):
    global retries
    name = (trail + " > " + suite.get("title", "")).strip(" >")
    for spec in suite.get("specs", []):
        for test in spec.get("tests", []):
            results = test.get("results", [])
            if len(results) > 1:
                retries += len(results) - 1
            if test.get("status") == "unexpected":
                err = ""
                for r in results:
                    e = (r.get("error") or {}).get("message", "")
                    if e:
                        err = e.splitlines()[0][:160]
                reasons.append("FAILED: %s > %s [%s] %s" % (name, spec.get("title"), test.get("projectName", ""), err))
    for sub in suite.get("suites", []):
        walk(sub, name)


for s in report.get("suites", []):
    walk(s)
if flaky:
    reasons.append("%d test(s) passed only on a retry" % flaky)
if skipped:
    reasons.append("%d test(s) were skipped" % skipped)
if retries:
    reasons.append("%d retried attempt(s)" % retries)
ok = passed >= 1 and failed == 0 and flaky == 0 and skipped == 0 and retries == 0
json.dump({"commit": commit, "ok": ok, "passed": passed, "failed": failed, "flaky": flaky, "skipped": skipped,
           "retries": retries, "reasons": reasons[:40]}, open(out_path, "w"), indent=2)
sys.exit(0 if ok else 1)
