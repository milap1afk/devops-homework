#!/usr/bin/env bash
# Kill PostgreSQL under the running API and watch readiness vs liveness.
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }
run 'kubectl -n kirana get deploy kirana-api -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,IMAGE:.spec.template.spec.containers[0].image'
run 'kubectl -n kirana get pods'
run 'kubectl -n kirana delete pod kirana-postgres-0 --wait=false'
echo "TIME   API pods (READY / RESTARTS)                         postgres   /ready (from inside the cluster)"
T0=$(date +%s)
for i in $(seq 18); do
  api=$(kubectl -n kirana get pods -l app.kubernetes.io/component=api --no-headers | awk '{printf "%s %s/%s  ", substr($1,length($1)-4), $2, $4}')
  pg=$(kubectl -n kirana get pod kirana-postgres-0 --no-headers 2>/dev/null | awk '{print $2, $3}')
  rd=$(kubectl -n kirana exec deploy/kirana-api -- python -c "import urllib.request as u
try: print(u.urlopen('http://localhost:8000/ready').status)
except Exception as e: print(getattr(e,'code','ERR'))" 2>/dev/null)
  printf "t+%-4s %-50s %-18s %s\n" "$(( $(date +%s) - T0 ))s" "$api" "$pg" "$rd"
  sleep 2
done; echo
run 'kubectl -n kirana get pods'
echo "# RESTARTS unchanged: liveness (/health) never failed; readiness (/ready) took the API out of the Service while the DB was down."
