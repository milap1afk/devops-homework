#!/usr/bin/env bash
# Session 20 demo. Usage: ./demo.sh [gitops|monitoring]
cd "$(dirname "$0")"
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }
say() { echo "# $*"; }
app() { kubectl -n argocd get application podinfo -o jsonpath='sync={.status.sync.status} health={.status.health.status} revision={.status.sync.revision}{"\n"}' | cut -c1-80; }
wait_app() { for i in $(seq 90); do s=$(app); case "$s" in *"sync=Synced health=Healthy"*) [ -z "$1" ] || kubectl -n podinfo get deploy podinfo -o jsonpath='{.status.readyReplicas}' | grep -qx "$1" && break;; esac; sleep 4; done; }
refresh() { kubectl -n argocd annotate application podinfo argocd.argoproj.io/refresh=hard --overwrite >/dev/null; }
PROM=http://localhost:9090
q() { python3 monitoring/promq.py query "$1"; }

gitops() {
  say "################ 1. Argo CD is installed ################"
  run 'kubectl -n argocd get pods'
  say "################ 2. Register the app: Git repo path -> cluster namespace ################"
  run 'cat gitops/argocd-application.yaml'
  run 'kubectl apply -f gitops/argocd-application.yaml'
  wait_app 2
  run 'kubectl -n argocd get application podinfo'
  run "kubectl -n argocd get application podinfo -o jsonpath='{range .status.resources[*]}{.kind}/{.name}  {.status}  {.health.status}{\"\\n\"}{end}'"
  run 'kubectl -n podinfo get deploy,svc,pods'
  run "kubectl -n podinfo exec deploy/podinfo -- wget -qO- localhost:9898 | grep -E '\"(hostname|version|message)\"'"
  say "################ 3. Change desired state IN GIT (replicas 2 -> 3, new message) ################"
  run "sed -i '' -e 's/replicas: 2/replicas: 3/' -e 's/Deployed by Argo CD from Git/Updated through a Git commit/' gitops/podinfo/deployment.yaml && git -C .. diff --stat"
  run "git -C .. commit -qam 'Session 20 GitOps demo: scale podinfo to 3 and change message' && git -C .. push -q origin main && git -C .. log --oneline -1"
  say "No kubectl apply. Argo CD notices the new commit (polls every ~3 min; a refresh is requested here to avoid waiting):"
  refresh; wait_app 3
  run 'kubectl -n argocd get application podinfo'
  run 'kubectl -n podinfo get deploy podinfo'
  run "kubectl -n podinfo exec deploy/podinfo -- wget -qO- localhost:9898 | grep '\"message\"'"
  run "kubectl -n argocd get application podinfo -o jsonpath='{range .status.history[*]}{.id}  {.revision}  {.deployedAt}{\"\\n\"}{end}' | cut -c1-80"
  say "################ 4. Drift: someone changes the cluster by hand ################"
  run 'kubectl -n podinfo scale deploy podinfo --replicas=5'
  run 'kubectl -n podinfo get deploy podinfo'
  say "selfHeal: Argo CD compares live state with Git and reverts the manual change:"
  for i in $(seq 30); do r=$(kubectl -n podinfo get deploy podinfo -o jsonpath='{.spec.replicas}'); [ "$r" = 3 ] && break; sleep 2; done
  run 'kubectl -n podinfo get deploy podinfo'
  run "kubectl -n argocd get application podinfo -o jsonpath='{.status.operationState.message}{\"\\n\"}{.status.operationState.syncResult.revision}{\"\\n\"}' | cut -c1-80"
  run "kubectl -n argocd logs statefulset/argocd-application-controller --tail=400 | grep -iE 'podinfo' | grep -iE 'selfheal|self-heal|OutOfSync|Initiated automated sync' | tail -3 | cut -c1-230"
}

monitoring() {
  kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 >/dev/null 2>&1 & PF1=$!
  kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093 >/dev/null 2>&1 & PF2=$!
  sleep 4
  say "################ Monitoring stack (kube-prometheus-stack via Helm) ################"
  run 'helm list -n monitoring'
  run 'kubectl -n monitoring get pods'
  run 'kubectl -n podinfo get servicemonitor,prometheusrule'
  say "################ Metrics: Prometheus discovered podinfo via the ServiceMonitor ################"
  run 'python3 monitoring/promq.py targets podinfo     # GET /api/v1/targets'
  say "generate some traffic so request metrics move"
  kubectl -n podinfo run loadgen --image=curlimages/curl:8.10.1 --restart=Never --command -- sh -c 'for i in $(seq 600); do curl -s -o /dev/null http://podinfo:9898/; curl -s -o /dev/null http://podinfo:9898/status/500; sleep 0.1; done' >/dev/null 2>&1
  sleep 75
  say "################ Metric queries (PromQL) ################"
  echo '$ up{job="podinfo"}                                   # 1 = scrape target healthy'; q 'up{job="podinfo"}'; echo
  echo '$ sum(rate(http_requests_total{job="podinfo"}[1m])) by (status)   # requests/s by HTTP status'
  curl -s --get "$PROM/api/v1/query" --data-urlencode 'query=sum(rate(http_requests_total{job="podinfo"}[1m])) by (status)' | python3 -c 'import json,sys; [print("  status", x["metric"].get("status"), "->", round(float(x["value"][1]),2), "req/s") for x in json.load(sys.stdin)["data"]["result"]]'; echo
  say "CPU utilisation (cores) per pod:"
  echo '$ sum(rate(container_cpu_usage_seconds_total{namespace="podinfo",container="podinfo"}[2m])) by (pod)'; q 'sum(rate(container_cpu_usage_seconds_total{namespace="podinfo",container="podinfo"}[2m])) by (pod)'; echo
  say "Memory utilisation (bytes) per pod:"
  echo '$ sum(container_memory_working_set_bytes{namespace="podinfo",container="podinfo"}) by (pod)'; q 'sum(container_memory_working_set_bytes{namespace="podinfo",container="podinfo"}) by (pod)'; echo
  say "Node CPU / memory used (%):"
  echo '$ 100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[2m])))'; q '100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[2m])))'; echo
  echo '$ 100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)'; q '100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)'; echo
  say "Application health (kube-state-metrics):"
  echo '$ kube_deployment_status_replicas_available{namespace="podinfo"}'; q 'kube_deployment_status_replicas_available{namespace="podinfo"}'; echo
  say "################ Logs ################"
  run 'kubectl -n podinfo logs deploy/podinfo --tail=3 | cut -c1-200'
  run 'kubectl -n podinfo logs -l app=podinfo --prefix --tail=2 | cut -c1-200'
  say "################ Alerts ################"
  run 'kubectl -n podinfo get prometheusrule podinfo-alerts -o jsonpath="{range .spec.groups[0].rules[*]}{.alert}: {.expr}{\"\\n\"}{end}"'
  run "curl -s $PROM/api/v1/rules?type=alert | python3 -c 'import json,sys; [print(\" \", r[\"name\"], \"->\", r[\"state\"]) for g in json.load(sys.stdin)[\"data\"][\"groups\"] if g[\"name\"]==\"podinfo.rules\" for r in g[\"rules\"]]'"
  say "Simulate an outage: pause Argo CD self-heal, scale podinfo to 0"
  run "kubectl -n argocd patch application podinfo --type merge -p '{\"spec\":{\"syncPolicy\":{\"automated\":{\"selfHeal\":false}}}}'"
  run 'kubectl -n podinfo scale deploy podinfo --replicas=0'
  for i in $(seq 40); do st=$(curl -s $PROM/api/v1/alerts | python3 -c 'import json,sys; print(" ".join(a["state"] for a in json.load(sys.stdin)["data"]["alerts"] if a["labels"]["alertname"]=="PodinfoDown"))'); echo "t+$((i*5))s PodinfoDown: ${st:-inactive}"; case "$st" in *firing*) break;; esac; sleep 5; done | uniq -f1 -c | awk '{$1=""; print}'
  echo
  run "curl -s $PROM/api/v1/alerts | python3 -c 'import json,sys; [print(\" \", a[\"labels\"][\"alertname\"], a[\"labels\"].get(\"severity\"), a[\"state\"], \"since\", a[\"activeAt\"][:19], \"-\", a[\"annotations\"][\"summary\"]) for a in json.load(sys.stdin)[\"data\"][\"alerts\"] if a[\"labels\"][\"alertname\"].startswith(\"Podinfo\")]'"
  sleep 20
  say "Alertmanager received it (this is what would page someone via Slack/email/PagerDuty):"
  run "curl -s http://localhost:9093/api/v2/alerts | python3 -c 'import json,sys; [print(\" \", a[\"labels\"][\"alertname\"], a[\"labels\"].get(\"severity\"), a[\"status\"][\"state\"], a[\"startsAt\"][:19]) for a in json.load(sys.stdin) if a[\"labels\"][\"alertname\"]==\"PodinfoDown\"]'"
  say "Recover: turn self-heal back on -> Argo CD restores replicas from Git -> alert resolves"
  run "kubectl -n argocd patch application podinfo --type merge -p '{\"spec\":{\"syncPolicy\":{\"automated\":{\"selfHeal\":true}}}}'"
  for i in $(seq 40); do r=$(kubectl -n podinfo get deploy podinfo -o jsonpath='{.status.readyReplicas}'); [ "$r" = 3 ] && break; sleep 3; done
  run 'kubectl -n podinfo get deploy podinfo'
  for i in $(seq 30); do st=$(curl -s $PROM/api/v1/alerts | python3 -c 'import json,sys; print(" ".join(a["state"] for a in json.load(sys.stdin)["data"]["alerts"] if a["labels"]["alertname"]=="PodinfoDown"))'); [ -z "$st" ] && break; sleep 5; done
  run "curl -s $PROM/api/v1/rules?type=alert | python3 -c 'import json,sys; [print(\" \", r[\"name\"], \"->\", r[\"state\"]) for g in json.load(sys.stdin)[\"data\"][\"groups\"] if g[\"name\"]==\"podinfo.rules\" for r in g[\"rules\"]]'"
  kubectl -n podinfo delete pod loadgen --ignore-not-found >/dev/null
  kill $PF1 $PF2; wait 2>/dev/null
}

parts=${1:-"gitops monitoring"}
for part in $parts; do $part > output-$part.txt 2>&1; echo "== $part ($(wc -l < output-$part.txt) lines)"; done
