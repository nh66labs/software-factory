#!/usr/bin/env python3
"""render-prompt.py <template> [<template>...]: print the templates concatenated with {{PLACEHOLDER}}s filled from the
environment (FACTORY_* and the variables the driver exports). Unknown placeholders are left as they are and reported on
stderr, so a typo in a prompt is visible instead of silently sent to an agent."""
import os
import re
import sys

parts = []
for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as fh:
        parts.append(fh.read())
text = "\n".join(parts)
missing = set()


def sub(m):
    key = m.group(1)
    if key in os.environ:
        return os.environ[key].replace("\\n", "\n") if key == "COMMIT_TRAILERS" else os.environ[key]
    missing.add(key)
    return m.group(0)


text = re.sub(r"\{\{([A-Z0-9_]+)\}\}", sub, text)
sys.stdout.write(text)
if missing:
    sys.stderr.write("render-prompt: unfilled placeholders: %s\n" % ", ".join(sorted(missing)))
