#!/usr/bin/env bash
# Session 12 demo on minikube. Usage: ./demo.sh [configmap|secret|ingress|troubleshooting]
cd "$(dirname "$0")"
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }
[ "${1:-}" = troubleshooting ] || { kubectl get ns s12 >/dev/null 2>&1 || kubectl create ns s12 >/dev/null; }

configmap() {
  kubectl -n s12 delete pod configmap-demo --ignore-not-found --now >/dev/null; kubectl -n s12 delete cm app-config --ignore-not-found >/dev/null
  echo "# ---- Create the ConfigMap (declarative) ----"
  run 'kubectl apply -f 01-configmap/configmap.yaml'
  echo "# ---- (same thing, imperative) ----"
  run 'kubectl -n s12 create configmap app-config-cli --from-literal=APP_ENV=staging --from-literal=LOG_LEVEL=debug --dry-run=client -o yaml'
  run 'kubectl -n s12 get configmap app-config'
  run 'kubectl -n s12 describe configmap app-config'
  echo "# ---- Inject into a Pod ----"
  run 'kubectl apply -f 01-configmap/pod.yaml'
  run 'kubectl -n s12 wait --for=condition=Ready pod/configmap-demo --timeout=120s'
  echo "# ---- Verify inside the container ----"
  run 'kubectl -n s12 exec configmap-demo -- sh -c "echo ENVIRONMENT=\$ENVIRONMENT; env | grep -E \"^(APP_|LOG_|MAX_)\" | sort"'
  run 'kubectl -n s12 exec configmap-demo -- ls -l /etc/config'
  run 'kubectl -n s12 exec configmap-demo -- cat /etc/config/app.properties'
  echo "# ---- Update the ConfigMap: mounted FILES refresh automatically, ENV VARS do not ----"
  run "kubectl -n s12 patch configmap app-config --type merge -p '{\"data\":{\"APP_COLOR\":\"green\"}}'"
  echo "# waiting for kubelet to sync the volume (up to ~60s)..."
  for i in $(seq 40); do [ "$(kubectl -n s12 exec configmap-demo -- cat /etc/config/APP_COLOR)" = green ] && break; sleep 3; done
  run 'kubectl -n s12 exec configmap-demo -- sh -c "echo file: \$(cat /etc/config/APP_COLOR)   env: \$APP_COLOR"'
  echo "# env vars are read only at container start -> restart the Pod (or rollout restart a Deployment) to pick them up"
}

secret() {
  kubectl -n s12 delete pod secret-demo --ignore-not-found --now >/dev/null; kubectl -n s12 delete secret db-credentials --ignore-not-found >/dev/null
  echo "# ---- Create the Secret from the command line (values never written to a file in Git) ----"
  run "kubectl -n s12 create secret generic db-credentials --from-literal=DB_USER=appuser --from-literal=DB_PASSWORD='Demo-P@ss-2026'"
  run 'kubectl -n s12 get secret db-credentials'
  echo "# describe hides the values, shows only sizes:"
  run "kubectl -n s12 describe secret db-credentials | sed -n '/^Data/,\$p'"
  echo "# but the stored data is only base64-ENCODED, not encrypted:"
  run "kubectl -n s12 get secret db-credentials -o jsonpath='{.data}'; echo"
  run "kubectl -n s12 get secret db-credentials -o jsonpath='{.data.DB_PASSWORD}' | base64 -d; echo"
  echo "# ---- Inject into a Pod ----"
  run 'kubectl apply -f 02-secret/pod.yaml'
  run 'kubectl -n s12 wait --for=condition=Ready pod/secret-demo --timeout=120s'
  echo "# ---- Verify inside the container ----"
  run 'kubectl -n s12 exec secret-demo -- sh -c "echo DB_USER=\$DB_USER; echo DB_PASSWORD=\$DB_PASSWORD"'
  run 'kubectl -n s12 exec secret-demo -- ls -lL /etc/secrets'
  run 'kubectl -n s12 exec secret-demo -- cat /etc/secrets/DB_PASSWORD; echo'
  run 'kubectl -n s12 exec secret-demo -- df -h /etc/secrets   # tmpfs: kept in memory, never on node disk'
  echo "# ---- Why a Secret YAML must not be committed: anyone with the repo can decode it ----"
  run "echo 'DB_PASSWORD: RGVtby1QQHNzLTIwMjY=' | awk '{print \$2}' | base64 -d; echo"
  run 'cat 02-secret/secret.example.yaml | grep -A3 stringData   # only a placeholder file is in Git'
}

ingress() {
  run 'kubectl get pods -n ingress-nginx'
  run 'kubectl get ingressclass'
  echo "# ---- Deploy the applications + Services ----"
  run 'kubectl apply -f 03-ingress/apps.yaml'
  run 'kubectl -n s12 rollout status deploy/shop --timeout=120s && kubectl -n s12 rollout status deploy/blog --timeout=120s'
  run 'kubectl -n s12 get deploy,svc'
  echo "# ---- Configure the Ingress ----"
  run 'kubectl apply -f 03-ingress/ingress.yaml'
  for i in $(seq 60); do a=$(kubectl -n s12 get ingress demo-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}'); [ -n "$a" ] && break; sleep 2; done
  run 'kubectl -n s12 get ingress demo-ingress'
  run "kubectl -n s12 describe ingress demo-ingress | sed -n '/^Rules:/,/^Annotations:/p'"
  echo "# ---- Access through the Ingress ----"
  echo "# (a) from inside the node, straight to the controller on port 80 of the node IP:"
  IP=$(minikube ip)
  run "minikube ssh -- curl -s --resolve kirana.local:80:$IP http://kirana.local/shop"
  run "minikube ssh -- curl -s --resolve kirana.local:80:$IP http://kirana.local/blog"
  run "minikube ssh -- curl -s --resolve blog.kirana.local:80:$IP http://blog.kirana.local/"
  echo "# (b) from the Mac, via a port-forward to the ingress controller Service:"
  kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8085:80 >/dev/null 2>&1 & PF=$!; sleep 4
  echo "# --resolve maps the hostname to 127.0.0.1 like an /etc/hosts entry"
  run "for p in shop shop blog blog; do curl -s --resolve kirana.local:8085:127.0.0.1 http://kirana.local:8085/\$p; done"
  run 'curl -s --resolve blog.kirana.local:8085:127.0.0.1 http://blog.kirana.local:8085/'
  echo "# ---- Verify routing: unknown host / path -> controller's default backend (404) ----"
  run 'curl -s -o /dev/null -w "HTTP %{http_code}\n" --resolve kirana.local:8085:127.0.0.1 http://kirana.local:8085/unknown'
  run 'curl -s -o /dev/null -w "HTTP %{http_code}\n" --resolve other.local:8085:127.0.0.1 http://other.local:8085/shop'
  kill $PF; wait $PF 2>/dev/null
  echo "# ---- Controller logs prove the requests went through ingress-nginx ----"
  run "kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=50 | grep -E 's12-(shop|blog)-svc' | tail -3 | sed -E 's/^[0-9.]+ /<client-ip> /'"
}

troubleshooting() {
  T=05-troubleshooting; N="kubectl -n s12-ts"
  kubectl delete ns s12-ts --ignore-not-found --wait --timeout=180s >/dev/null 2>&1
  applog() { $N logs deploy/yatri-backend --tail=${1:-3}; }
  echo "################ SETUP: PostgreSQL (correct password) + backend that logs in every 5s ################"
  run "kubectl apply -f $T/postgres.yaml"
  run "$N rollout status deploy/yatri-postgres --timeout=240s"
  run "kubectl apply -f $T/broken-secret.yaml -f $T/app.yaml"
  $N rollout status deploy/yatri-backend --timeout=180s >/dev/null; sleep 12
  echo "################ 1. IDENTIFY THE PROBLEM ################"
  echo "# Every Pod is Running and Ready, nothing restarts -> 'kubectl get pods' looks healthy:"
  run "$N get pods"
  echo "# ...but the backend cannot log in to the database:"
  run 'applog 3'
  echo "################ 2. TROUBLESHOOTING COMMANDS ################"
  echo "# The server side confirms it is a credential problem, not networking/DNS (the connection reached Postgres):"
  run "$N logs deploy/yatri-postgres --tail=40 | grep -A1 'password authentication failed' | tail -2"
  echo "# Which Secret/key does the app use?"
  run "$N get deploy yatri-backend -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{\" <- \"}{.valueFrom.secretKeyRef.name}{\"/\"}{.valueFrom.secretKeyRef.key}{\"\\n\"}{end}'"
  echo "# describe hides values but shows SIZES: 'secretpassword' is 14 characters, the Secret holds 15 bytes"
  run "$N describe secret yatri-db-secret | sed -n '/^Data/,\$p'"
  run "$N get secret yatri-db-secret -o jsonpath='{.data.POSTGRES_PASSWORD}'; echo"
  run "$N get secret yatri-db-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d | xxd"
  echo "# compare with the password the database server was created with:"
  run "$N get secret postgres-server-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d | xxd"
  echo "# and what the running container actually received (length of the env var):"
  run "$N exec deploy/yatri-backend -- sh -c 'echo PGPASSWORD length: \${#PGPASSWORD}'"
  echo "# reproduce how the value was produced:"
  run 'echo "secretpassword" | xxd'
  run 'echo "secretpassword" | base64'
  run 'echo -n "secretpassword" | base64'
  echo "################ 3. ROOT CAUSE ################"
  echo "# The password was encoded with 'echo \"secretpassword\" | base64'. echo appends a newline (0x0a), so the Secret"
  echo "# stores 'secretpassword\\n' (15 bytes, base64 ending in 'K' instead of '='). The app sends that exact string,"
  echo "# Postgres compares it with 'secretpassword' and rejects it: password authentication failed."
  echo "################ 4. FIX ################"
  run "diff $T/broken-secret.yaml $T/fixed-secret.yaml"
  run "kubectl apply -f $T/fixed-secret.yaml"
  run "$N describe secret yatri-db-secret | sed -n '/^Data/,\$p'"
  sleep 10
  echo "# The Secret is fixed, but the app STILL fails: env vars are copied into the container only when it starts"
  run 'applog 2'
  run "$N rollout restart deploy/yatri-backend && $N rollout status deploy/yatri-backend --timeout=180s"
  sleep 12
  echo "################ 5. VERIFY (after) ################"
  run "$N get pods"
  run 'applog 3'
  run "$N exec deploy/yatri-backend -- sh -c 'echo PGPASSWORD length: \${#PGPASSWORD}'"
  run "$N logs deploy/yatri-postgres --since=20s | grep -c 'password authentication failed' || true"
  kubectl delete ns s12-ts --wait=false >/dev/null
}

parts=${1:-"configmap secret ingress"}
for part in $parts; do $part > output-$part.txt 2>&1; echo "== $part ($(wc -l < output-$part.txt) lines)"; done
