#!/usr/bin/env python3
"""Git merge driver for JSON files that many parallel stories add keys to (translation files, registries): a three-way
merge BY KEY, so two stories that each add strings no longer conflict. Exit 1 only when both sides changed the SAME key
differently. Register it once:
    git config merge.jsonkeys.driver "python3 /path/to/merge-json-keys.py %O %A %B"
    echo 'src/locales/**/*.json merge=jsonkeys' >> .gitattributes
Usage (git calls it): merge-json-keys.py %O %A %B  -> writes the result into %A."""
import json
import sys

MISSING = object()


def merge(base, ours, theirs):
    if ours == theirs:
        return ours
    if base == ours:
        return theirs
    if base == theirs:
        return ours
    if isinstance(ours, dict) and isinstance(theirs, dict) and isinstance(base, dict):
        out = {}
        for key in list(ours) + [k for k in theirs if k not in ours]:
            value = merge(base.get(key, MISSING), ours.get(key, MISSING), theirs.get(key, MISSING))
            if value is not MISSING:
                out[key] = value
        return out
    raise ValueError("conflict")


def load(path):
    with open(path, encoding="utf-8") as fh:
        return json.loads(fh.read())


try:
    base, ours, theirs = (load(p) for p in sys.argv[1:4])
    result = merge(base, ours, theirs)
except Exception:  # noqa: BLE001
    sys.exit(1)
with open(sys.argv[2], "w", encoding="utf-8") as fh:
    fh.write(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
