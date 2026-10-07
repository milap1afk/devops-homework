#!/usr/bin/env bash
# Session 10 demo on minikube. Usage: ./demo.sh [rolling|bluegreen|canary|recreate|lifecycle]
# Each part writes output-<part>.txt
cd "$(dirname "$0")"
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }
tester() { kubectl get pod tester >/dev/null 2>&1 || { kubectl run tester --image=curlimages/curl:8.10.1 --restart=Never --command -- sleep infinity >/dev/null; kubectl wait --for=condition=Ready pod/tester --timeout=120s >/dev/null; }; }

# wait until Service $1 has exactly $2 ready endpoints (selector changes / scaling take a moment)
wait_ep() { for i in $(seq 60); do n=$(kubectl get endpointslices -l kubernetes.io/service-name=$1 -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}x{end}' | wc -c | tr -d ' '); [ "$n" = "$2" ] && { sleep 6; return; }; sleep 1; done; }   # +6s for kube-proxy to sync rules

rolling() {
  kubectl delete deploy web-rolling --ignore-not-found >/dev/null
  run 'kubectl apply -f 01-rolling-update/deployment.yaml'
  run 'kubectl rollout status deployment/web-rolling --timeout=180s'
  run 'kubectl get deploy web-rolling -o wide'
  run "kubectl describe deploy web-rolling | grep -E 'StrategyType|RollingUpdateStrategy|MinReadySeconds'"
  run 'kubectl get pods -l app=web-rolling -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image,STATUS:.status.phase'
  echo "# ---- Perform the update: nginx:1.26 -> nginx:1.27 ----"
  run 'kubectl set image deployment/web-rolling nginx=nginx:1.27'
  run 'kubectl annotate deployment/web-rolling kubernetes.io/change-cause="update to nginx:1.27" --overwrite'
  echo "# Watching mid-rollout (old and new Pods side by side, max 5 = replicas 4 + maxSurge 1):"
  for i in 1 2 3 4 5 6; do
    echo "--- t+$((i*4))s"
    kubectl get pods -l app=web-rolling --no-headers -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image,READY:.status.containerStatuses[0].ready,PHASE:.status.phase 2>&1
    sleep 4
  done; echo
  run 'kubectl rollout status deployment/web-rolling --timeout=180s'
  run 'kubectl get rs -l app=web-rolling'
  run 'kubectl get pods -l app=web-rolling -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image,STATUS:.status.phase'
  run 'kubectl rollout history deployment/web-rolling'
  run "kubectl describe deploy web-rolling | sed -n '/Events:/,\$p'"
  echo "# Bonus: roll back to the previous revision"
  run 'kubectl rollout undo deployment/web-rolling && kubectl rollout status deployment/web-rolling --timeout=180s'
  run "kubectl get deploy web-rolling -o jsonpath='{.spec.template.spec.containers[0].image}{\"\\n\"}'"
}

bluegreen() {
  tester; kubectl delete -f 02-blue-green --ignore-not-found >/dev/null
  run 'kubectl apply -f 02-blue-green/blue.yaml -f 02-blue-green/service.yaml'
  run 'kubectl rollout status deploy/app-blue --timeout=120s'
  wait_ep shop 2
  run 'for i in 1 2 3; do kubectl exec tester -- curl -s http://shop; done'
  echo "# Deploy GREEN alongside BLUE (no traffic yet)"
  run 'kubectl apply -f 02-blue-green/green.yaml && kubectl rollout status deploy/app-green --timeout=120s'
  run 'kubectl get pods -l app=shop -L version'
  run "kubectl get svc shop -o jsonpath='selector: {.spec.selector}{\"\\n\"}'"
  run 'kubectl get endpointslices -l kubernetes.io/service-name=shop -o custom-columns=NAME:.metadata.name,ENDPOINTS:.endpoints[*].addresses[0]'
  run 'for i in 1 2 3; do kubectl exec tester -- curl -s http://shop; done'
  echo "# ---- SWITCH traffic to GREEN (one atomic selector change) ----"
  run "kubectl patch service shop -p '{\"spec\":{\"selector\":{\"app\":\"shop\",\"version\":\"green\"}}}'"
  wait_ep shop 2; sleep 1
  run "kubectl get svc shop -o jsonpath='selector: {.spec.selector}{\"\\n\"}'"
  run 'kubectl get endpointslices -l kubernetes.io/service-name=shop -o custom-columns=NAME:.metadata.name,ENDPOINTS:.endpoints[*].addresses[0]'
  run "kubectl get pods -l version=green -o custom-columns=POD:.metadata.name,IP:.status.podIP"
  run 'for i in 1 2 3; do kubectl exec tester -- curl -s http://shop; done'
  echo "# ---- Instant rollback = switch the selector back ----"
  run "kubectl patch service shop -p '{\"spec\":{\"selector\":{\"version\":\"blue\"}}}' && sleep 2 && kubectl exec tester -- curl -s http://shop"
  run "kubectl patch service shop -p '{\"spec\":{\"selector\":{\"version\":\"green\"}}}' && sleep 2 && kubectl exec tester -- curl -s http://shop"
  echo "# Once green is verified, retire blue"
  run 'kubectl scale deploy app-blue --replicas=0 && kubectl get deploy -l app=shop 2>/dev/null; kubectl get deploy app-blue app-green'
}

canary() {
  tester; kubectl delete -f 03-canary --ignore-not-found >/dev/null
  run 'kubectl apply -f 03-canary/stable.yaml -f 03-canary/service.yaml'
  run 'kubectl rollout status deploy/app-stable --timeout=180s'
  run 'kubectl apply -f 03-canary/canary.yaml && kubectl rollout status deploy/app-canary --timeout=120s'
  wait_ep checkout 10
  run 'kubectl get deploy -l app=checkout 2>/dev/null; kubectl get deploy app-stable app-canary'
  run 'kubectl get pods -l app=checkout -L track --no-headers | awk "{print \$NF}" | sort | uniq -c'
  echo "# Send 200 requests through the Service and count which version answered"
  run "kubectl exec tester -- sh -c 'for i in \$(seq 200); do curl -s http://checkout; done' | sort | uniq -c"
  echo "# Canary looks healthy -> increase its share to ~30% (7 stable : 3 canary)"
  run 'kubectl scale deploy app-stable --replicas=7 && kubectl scale deploy app-canary --replicas=3 && kubectl rollout status deploy/app-canary --timeout=120s && kubectl rollout status deploy/app-stable --timeout=120s'
  wait_ep checkout 10
  run 'kubectl get pods -l app=checkout -L track --no-headers | awk "{print \$NF}" | sort | uniq -c'
  run "kubectl exec tester -- sh -c 'for i in \$(seq 200); do curl -s http://checkout; done' | sort | uniq -c"
}

recreate() {
  kubectl delete deploy web-recreate --ignore-not-found --wait >/dev/null
  run 'kubectl apply -f 04-recreate/deployment.yaml && kubectl rollout status deploy/web-recreate --timeout=180s'
  run "kubectl describe deploy web-recreate | grep StrategyType"
  run 'kubectl get pods -l app=web-recreate -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image,STATUS:.status.phase'
  echo "# Start a watch, then update the image. Every OLD pod is terminated before ANY new pod is created."
  kubectl get pods -l app=web-recreate --watch-only -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image,PHASE:.status.phase,DELETING:.metadata.deletionTimestamp > /tmp/recreate-watch.txt 2>&1 &
  W=$!; sleep 2
  run 'kubectl set image deploy/web-recreate nginx=nginx:1.27'
  run 'kubectl rollout status deploy/web-recreate --timeout=180s'
  sleep 2; kill $W
  echo '$ kubectl get pods -l app=web-recreate --watch-only   (events in order, timestamped by kubectl)'
  cat /tmp/recreate-watch.txt; echo
  run "kubectl describe deploy web-recreate | sed -n '/Events:/,\$p'"
  echo "# Note the events: 'Scaled down ... from 3 to 0' happens BEFORE 'Scaled up ... to 3'"
  run 'kubectl get rs -l app=web-recreate'
}

lifecycle() {
  kubectl delete -f 05-pod-lifecycle --ignore-not-found --wait=false >/dev/null 2>&1; sleep 3
  for f in 05-pod-lifecycle/*.yaml; do
    pod=$(grep -m1 '  name:' "$f" | awk '{print $2}')
    echo "################ $f ################"
    run "kubectl apply -f $f"
    case "$pod" in
      lifecycle-init)
        echo "# polling STATUS every second:"
        for i in $(seq 14); do kubectl get pod $pod --no-headers; sleep 1; done | uniq -f2 -c; echo ;;
      lifecycle-probes)
        echo "# polling until the readiness probe passes (READY 0/1 -> 1/1):"
        for i in $(seq 20); do l=$(kubectl get pod $pod --no-headers); echo "$l"; case "$l" in *" 1/1 "*) break;; esac; sleep 2; done; echo ;;
      lifecycle-crashloop)
        echo "# polling every 5s: Running -> Error -> CrashLoopBackOff, restarts climbing, back-off growing"
        for i in $(seq 40); do l=$(kubectl get pod $pod --no-headers); echo "$l"; case "$l" in *CrashLoopBackOff*) break;; esac; sleep 5; done; echo ;;
      lifecycle-pending) sleep 5 ;;
      *) sleep 15 ;;
    esac
    run "kubectl get pod $pod -o wide"
    run "kubectl get pod $pod -o jsonpath='phase={.status.phase}  reason={.status.containerStatuses[0].state.*.reason}  restarts={.status.containerStatuses[0].restartCount}{\"\\n\"}'"
    run "kubectl describe pod $pod | sed -n '/^Conditions:/,/^Volumes:/p' | grep -v '^Volumes:'"
    run "kubectl describe pod $pod | sed -n '/^Events:/,\$p'"
    case "$pod" in
      lifecycle-succeeded|lifecycle-failed|lifecycle-crashloop) run "kubectl logs $pod" ;;
      lifecycle-init) run "kubectl exec $pod -c web -- cat /usr/share/nginx/html/index.html" ;;
      lifecycle-probes)
        run "kubectl exec $pod -- cat /usr/share/nginx/html/hook.txt"
        echo "# Delete it: preStop hook runs, then the container gets SIGTERM within the grace period"
        run "kubectl delete pod $pod --wait=false && sleep 2 && kubectl get pod $pod"
        run "sleep 6; kubectl get pod $pod"
        ;;
    esac
  done
}

parts=${1:-"rolling bluegreen canary recreate lifecycle"}
for p in $parts; do $p > output-$p.txt 2>&1; echo "== $p done ($(wc -l < output-$p.txt) lines)"; done
