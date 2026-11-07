#!/usr/bin/env python3
"""verdict-from-junit.py <junit.xml> <commit> <verdict-out.json>   Same contract as verdict-from-playwright.py for any
runner that writes JUnit XML (pytest --junitxml, go-junit-report, gradle, cypress with a junit reporter, ...)."""
import json
import sys
import xml.etree.ElementTree as ET

xml_path, commit, out_path = sys.argv[1:4]
root = ET.parse(xml_path).getroot()
cases = root.iter("testcase")
passed = failed = skipped = 0
reasons = []
for case in cases:
    if case.find("skipped") is not None:
        skipped += 1
    elif case.find("failure") is not None or case.find("error") is not None:
        failed += 1
        node = case.find("failure") if case.find("failure") is not None else case.find("error")
        reasons.append("FAILED: %s.%s %s" % (case.get("classname", ""), case.get("name", ""), (node.get("message") or "")[:120]))
    else:
        passed += 1
if skipped:
    reasons.append("%d test(s) were skipped" % skipped)
ok = passed >= 1 and failed == 0 and skipped == 0
json.dump({"commit": commit, "ok": ok, "passed": passed, "failed": failed, "skipped": skipped, "flaky": 0, "retries": 0,
           "reasons": reasons[:40]}, open(out_path, "w"), indent=2)
sys.exit(0 if ok else 1)
