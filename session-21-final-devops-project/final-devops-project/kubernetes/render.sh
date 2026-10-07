#!/usr/bin/env bash
# Regenerates the plain manifests in kubernetes/ (and monitoring/) from the Helm chart, so they never drift.
cd "$(dirname "$0")/.."
helm template kirana helm/kirana -n kirana -f helm/kirana/values-minikube.yaml --set monitoring.grafanaDashboard=false | python3 -c '
import re, sys
docs = [d for d in sys.stdin.read().split("\n---\n") if "kind:" in d]
files = {"ConfigMap": "kubernetes/configmap.yaml",
         "HorizontalPodAutoscaler": "kubernetes/hpa.yaml", "Ingress": "kubernetes/ingress.yaml",
         "StatefulSet": "kubernetes/postgres-statefulset.yaml",
         "PrometheusRule": "monitoring/prometheusrule.yaml", "ServiceMonitor": "monitoring/servicemonitor.yaml"}
out = {}
for d in docs:
    kind = re.search(r"^kind: (\S+)", d, re.M).group(1)
    name = re.search(r"^  name: (\S+)", d, re.M).group(1)
    tier = "postgres" if "postgres" in name else "backend" if "backend" in name else "frontend"
    f = files.get(kind) or f"kubernetes/{tier}.yaml"
    if kind == "StatefulSet" or (kind == "Service" and tier == "postgres"):
        f = "kubernetes/postgres.yaml"
    out.setdefault(f, []).append(re.sub(r"^# Source: .*\n", "", d, flags=re.M).strip())
hdr = "# Rendered from ../helm/kirana by kubernetes/render.sh. Edit the chart, not this file.\n"
for f, ds in out.items():
    open(f, "w").write(hdr + "\n---\n".join(ds) + "\n")
print("rendered:", ", ".join(sorted(out)))
'
