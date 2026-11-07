#!/usr/bin/env python3
"""Turn one agent run's output into a single status line the driver can act on.

    parse-result.py <output-file>      prints:  <STATUS> | turns=N tokens=N out=N cost=$X

STATUS is what the agent wrote after "RESULT:" (DONE <sha> | BLOCKED <reason>), or one of the driver's own verdicts:

    INFRA <reason>          the run never really ran: network down, API unreachable, rate or usage limit, overloaded
                            service, killed. The driver retries these WITHOUT counting a failed attempt, because
                            nothing was learned about the story (a night of ENOTFOUND once parked three finished stories).
    BLOCKED no-result-line  the agent ended its turn without the RESULT line (usually it started a background command
                            and stopped to "check later"): a product-level failure, retried from the worktree.
    BLOCKED no-json-output  the run left no readable output.

Understands the JSON of `claude -p --output-format json` and falls back to plain text (any agent that prints the RESULT
line). Uses only the standard library; run it with `python3 -I`.
"""
import json
import re
import sys

INFRA_PATTERNS = [
    r"ENOTFOUND", r"ECONNRESET", r"ECONNREFUSED", r"ETIMEDOUT", r"EAI_AGAIN",
    r"connection[_ ]failed", r"can'?t reach the api", r"network (is )?(unreachable|error)",
    r"rate[ _-]?limit", r"usage limit", r"limit reached", r"quota", r"overloaded",
    r"\b429\b", r"\b50[234]\b", r"service unavailable", r"credit balance", r"temporarily unavailable",
    r"request timed out", r"stream (closed|ended) unexpectedly",
]
INFRA_RE = re.compile("|".join(INFRA_PATTERNS), re.I)


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else ""
    raw = read(path)
    if not raw.strip():
        print("INFRA empty-output | turns=0 tokens=0 out=0 cost=$0.00")
        return
    data = None
    try:
        data = json.loads(raw)
    except ValueError:
        data = None

    if isinstance(data, dict):
        text = (data.get("result") or "").strip()
        models = list((data.get("modelUsage") or {}).values())

        def total(key):
            return sum(m.get(key, 0) for m in models)

        tokens = total("inputTokens") + total("outputTokens") + total("cacheReadInputTokens") + total("cacheCreationInputTokens")
        out = total("outputTokens")
        turns = data.get("num_turns")
        cost = data.get("total_cost_usd") or 0
        is_error = bool(data.get("is_error")) or bool(data.get("api_error"))
        api_error = str(data.get("api_error") or "")
    else:
        text, tokens, out, turns, cost, is_error, api_error = raw.strip(), 0, 0, None, 0, False, ""

    lines = [l for l in text.splitlines() if l.startswith("RESULT:")]
    if lines:
        status = lines[-1][len("RESULT:"):].strip()
    elif is_error or (not text and INFRA_RE.search(raw)) or INFRA_RE.search(text[:400]):
        why = (api_error or text[:120] or "agent error").replace("\n", " ")
        status = "INFRA " + why
    elif data is None and not text:
        status = "BLOCKED no-json-output"
    else:
        status = "BLOCKED no-result-line"
    print("%s | turns=%s tokens=%s out=%s cost=$%.2f " % (status, turns, tokens, out, float(cost)))


if __name__ == "__main__":
    main()
