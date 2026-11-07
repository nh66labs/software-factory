#!/usr/bin/env python3
"""queue.py [--plan DIR] [--lanes N] [--out DIR] [--exclude-built FILE]

Orders the plan's stories by build dependency (never by importance: priority labels do not decide build order) and deals
them into N lane queue files (queues/lane-1.txt ...). A story is placed after every story it depends on in its own lane
or, when the dependency sits in another lane, the driver defers it (BLOCKED deps) until the other lane has built it, so
lanes never deadlock as long as the plan has no cycle (plan-check.py).

Lane assignment keeps an epic's stories together (a lane owns an area, which keeps merge conflicts down) and balances the
lanes by story count. Prints the order and writes the files when --out is given.
"""
import argparse
import glob
import os
import re

ap = argparse.ArgumentParser()
ap.add_argument("--plan", default="plan")
ap.add_argument("--lanes", type=int, default=2)
ap.add_argument("--out")
ap.add_argument("--exclude-built", help="file with one already built story id per line")
args = ap.parse_args()

HEAD = re.compile(r"^#{2,4}\s+([A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+)\s*[·\-:–]\s*(.+)$")
stories, order = {}, []
for path in sorted(glob.glob(os.path.join(args.plan, "**", "*.md"), recursive=True)):
    cur = None
    for line in open(path, encoding="utf-8"):
        m = HEAD.match(line.rstrip())
        if m:
            cur = m.group(1)
            stories[cur] = {"deps": [], "epic": os.path.basename(path)}
            order.append(cur)
        elif cur and line.strip().lower().startswith("- depends on:"):
            stories[cur]["deps"] = [x.strip() for x in line.split(":", 1)[1].split(",") if x.strip() and x.strip().lower() not in ("none", "-")]
built = set()
if args.exclude_built and os.path.isfile(args.exclude_built):
    built = set(l.strip() for l in open(args.exclude_built) if l.strip())

done, topo = set(built), []
remaining = [s for s in order if s not in built]
while remaining:
    ready = [s for s in remaining if all(d in done or d not in stories for d in stories[s]["deps"])]
    if not ready:
        raise SystemExit("queue: cycle or missing dependency among: " + ", ".join(remaining[:8]))
    for s in ready:
        topo.append(s)
        done.add(s)
    remaining = [s for s in remaining if s not in done]

lanes = [[] for _ in range(max(1, args.lanes))]
epic_lane = {}
for s in topo:
    e = stories[s]["epic"]
    if e not in epic_lane:
        epic_lane[e] = min(range(len(lanes)), key=lambda i: len(lanes[i]))
    lanes[epic_lane[e]].append(s)
for i, lane in enumerate(lanes, 1):
    print("lane-%d (%d stories): %s" % (i, len(lane), " ".join(lane[:12]) + (" ..." if len(lane) > 12 else "")))
    if args.out:
        os.makedirs(args.out, exist_ok=True)
        with open(os.path.join(args.out, "lane-%d.txt" % i), "w") as fh:
            fh.write("\n".join(lane) + "\n")
