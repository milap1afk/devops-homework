#!/usr/bin/env python3
"""Tiny Prometheus HTTP API client.  promq.py query '<promql>'  |  promq.py targets <job>"""
import json
import sys
import urllib.parse
import urllib.request

PROM = "http://localhost:9090"
KEEP = ("job", "pod", "instance", "status", "deployment", "namespace")


def get(path, **params):
    url = f"{PROM}{path}?{urllib.parse.urlencode(params)}"
    with urllib.request.urlopen(url) as r:
        return json.load(r)["data"]


if sys.argv[1] == "query":
    result = get("/api/v1/query", query=sys.argv[2])["result"]
    for x in result:
        labels = ",".join(f"{k}={v}" for k, v in x["metric"].items() if k in KEEP)
        value = round(float(x["value"][1]), 4)
        print(f"  {{{labels}}}  {value}")
    if not result:
        print("  (no data)")
elif sys.argv[1] == "targets":
    for t in get("/api/v1/targets", state="active")["activeTargets"]:
        if t["labels"].get("job") == sys.argv[2]:
            print(f"  job={t['labels']['job']}  {t['scrapeUrl']}  health={t['health']}  lastScrape={t['lastScrape'][:19]}")
