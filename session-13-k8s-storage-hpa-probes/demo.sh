#!/usr/bin/env bash
# Session 13 demo on minikube. Usage: ./demo.sh [volumes|hpa|mini|minihpa|coursehpa]
cd "$(dirname "$0")"
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }
case "${1:-}" in mini|minihpa|coursehpa) ;; *) kubectl get ns s13 >/dev/null 2>&1 || kubectl create ns s13 >/dev/null;; esac
E=01-kubernetes-volumes/examples

volumes() {
  kubectl -n s13 delete pod emptydir-demo hostpath-demo static-pv-demo --ignore-not-found --now >/dev/null 2>&1
  kubectl -n s13 delete deploy notes-app --ignore-not-found >/dev/null; kubectl -n s13 delete pvc --all --wait >/dev/null 2>&1
  kubectl delete pv manual-pv --ignore-not-found >/dev/null; kubectl delete sc fast-retain --ignore-not-found >/dev/null
  minikube ssh -- sudo rm -rf /tmp/s13-hostpath /tmp/s13-manual-pv >/dev/null 2>&1

  echo "################ emptyDir ################"
  run "kubectl apply -f $E/01-emptydir.yaml && kubectl -n s13 wait --for=condition=Ready pod/emptydir-demo --timeout=120s"
  sleep 6
  run 'kubectl -n s13 exec emptydir-demo -c reader -- cat /input/log.txt'
  run 'kubectl -n s13 exec emptydir-demo -c reader -- sh -c "echo hack >> /input/log.txt"   # reader mounted it readOnly'
  run "kubectl -n s13 get pod emptydir-demo -o jsonpath='{.metadata.uid}'; echo"
  UID1=$(kubectl -n s13 get pod emptydir-demo -o jsonpath='{.metadata.uid}')
  run "minikube ssh -- sudo ls /var/lib/kubelet/pods/$UID1/volumes/kubernetes.io~empty-dir/shared"
  run 'kubectl -n s13 delete pod emptydir-demo --wait'
  echo "# give the kubelet a moment to tear down the Pod's volumes"
  for i in $(seq 20); do minikube ssh -- sudo test -d /var/lib/kubelet/pods/$UID1 >/dev/null 2>&1 || break; sleep 3; done
  run "minikube ssh -- sudo ls /var/lib/kubelet/pods/$UID1/volumes/kubernetes.io~empty-dir/shared 2>&1 || echo 'gone: emptyDir is deleted with the Pod'"

  echo "################ hostPath ################"
  run "kubectl apply -f $E/02-hostpath.yaml && kubectl -n s13 wait --for=condition=Ready pod/hostpath-demo --timeout=120s"
  run 'minikube ssh -- cat /tmp/s13-hostpath/hostpath.txt'
  run 'kubectl -n s13 delete pod hostpath-demo --now'
  run "kubectl apply -f $E/02-hostpath.yaml && kubectl -n s13 wait --for=condition=Ready pod/hostpath-demo --timeout=120s"
  echo "# the file is still on the node and now has 2 lines (survived the Pod)"
  run 'minikube ssh -- cat /tmp/s13-hostpath/hostpath.txt'

  echo "################ Static PersistentVolume + PersistentVolumeClaim ################"
  run "kubectl apply -f $E/03-static-pv-pvc.yaml"
  kubectl -n s13 wait --for=condition=Ready pod/static-pv-demo --timeout=120s >/dev/null
  run 'kubectl get pv manual-pv'
  run 'kubectl -n s13 get pvc manual-pvc'
  run 'kubectl -n s13 exec static-pv-demo -- sh -c "echo order-1001 > /data/orders.txt; cat /data/orders.txt"'
  run 'kubectl -n s13 delete pod static-pv-demo --now && kubectl -n s13 delete pvc manual-pvc'
  echo "# reclaimPolicy Retain -> PV becomes Released, data kept on disk"
  run 'kubectl get pv manual-pv'
  run 'minikube ssh -- cat /tmp/s13-manual-pv/orders.txt'

  echo "################ StorageClass ################"
  run 'kubectl get storageclass'
  run "kubectl apply -f $E/04-storageclass.yaml && kubectl get storageclass fast-retain"

  echo "################ Dynamic provisioning ################"
  run 'kubectl get pv | grep -c dynamic || true   # no PV exists for it yet'
  run "kubectl apply -f $E/05-dynamic-pvc.yaml"
  kubectl -n s13 rollout status deploy/notes-app --timeout=120s >/dev/null
  run 'kubectl -n s13 get pvc dynamic-pvc'
  run "kubectl get pv -o custom-columns=NAME:.metadata.name,CAPACITY:.spec.capacity.storage,RECLAIM:.spec.persistentVolumeReclaimPolicy,STATUS:.status.phase,CLAIM:.spec.claimRef.name,STORAGECLASS:.spec.storageClassName | grep -E 'NAME|dynamic-pvc'"
  run "kubectl -n s13 describe pvc dynamic-pvc | sed -n '/^Events:/,\$p'"
  run 'kubectl -n s13 exec deploy/notes-app -- cat /data/notes.txt'
  echo "# Delete the Pod -> Deployment creates a new one -> same PVC -> data survives"
  run 'kubectl -n s13 delete pod -l app=notes --now && kubectl -n s13 rollout status deploy/notes-app --timeout=120s'
  sleep 3
  run 'kubectl -n s13 exec deploy/notes-app -- cat /data/notes.txt'
}

hpa() {
  kubectl -n s13 delete -f 02-hpa/load-generator.yml --ignore-not-found >/dev/null 2>&1
  kubectl -n s13 delete -f 02-hpa/hpa.yml --ignore-not-found --wait >/dev/null 2>&1
  echo "######## 1. Deploy the application ########"
  run 'kubectl apply -f 02-hpa/hpa.yml'
  run 'kubectl -n s13 rollout status deploy/php-apache --timeout=180s'
  run 'kubectl -n s13 get deploy,svc php-apache'
  echo "######## 2-3. Configure + verify HPA ########"
  echo "# (equivalent imperative command: kubectl autoscale deployment php-apache --cpu-percent=50 --min=1 --max=8)"
  echo "# waiting for metrics-server to report the first CPU sample..."
  for i in $(seq 40); do kubectl -n s13 get hpa php-apache --no-headers | grep -q 'cpu: [0-9]' && break; sleep 5; done
  run 'kubectl -n s13 get hpa'
  run "kubectl -n s13 describe hpa php-apache | grep -vE '^(Annotations|CreationTimestamp|Labels):'"
  run 'kubectl -n s13 top pods'
  echo "######## 4-5. Deploy load generator / increase load ########"
  run 'kubectl apply -f 02-hpa/load-generator.yml'
  echo "######## 6-7. Observe CPU utilisation and Pod scaling (sampled every 20s) ########"
  echo "TIME   HPA(cpu: current/target)   REPLICAS   POD CPU (kubectl top)"
  T0=$(date +%s)
  for i in $(seq 16); do
    h=$(kubectl -n s13 get hpa php-apache --no-headers | awk '{print $3, $4, $5, $6, $7}')
    top=$(kubectl -n s13 top pods -l run=php-apache --no-headers 2>/dev/null | awk '{printf "%s ", $2}')
    printf "t+%-4s %s   |  %s\n" "$(( $(date +%s) - T0 ))s" "$h" "$top"
    sleep 20
  done; echo
  run 'kubectl -n s13 get hpa'
  run 'kubectl -n s13 get pods -l run=php-apache -o wide'
  run 'kubectl -n s13 top pods'
  run "kubectl -n s13 describe hpa php-apache | sed -n '/^Events:/,\$p'"
  echo "######## Stop the load -> watch scale-down ########"
  run 'kubectl -n s13 delete -f 02-hpa/load-generator.yml'
  T0=$(date +%s)
  for i in $(seq 12); do
    h=$(kubectl -n s13 get hpa php-apache --no-headers | awk '{print $3, $4, $5, $6, $7}')
    printf "t+%-4s %s\n" "$(( $(date +%s) - T0 ))s" "$h"
    r=$(kubectl -n s13 get deploy php-apache -o jsonpath='{.status.replicas}')
    [ "$r" = 1 ] && [ $i -gt 3 ] && break
    sleep 20
  done; echo
  run 'kubectl -n s13 get hpa'
  run "kubectl -n s13 describe hpa php-apache | sed -n '/^Events:/,\$p'"
  run 'kubectl -n s13 get pods -l run=php-apache'
}

hpaline() { kubectl -n $1 get hpa $2 --no-headers | awk '{print $3, $4, $5, $6, $7}'; }

mini() {
  M=03-mini-project; N="kubectl -n s13-mini"
  kubectl delete ns s13-mini --ignore-not-found --wait --timeout=180s >/dev/null 2>&1
  echo "################ 5.1 Namespace ################"
  run "kubectl apply -f $M/namespace.yaml"
  echo "################ 5.2 PersistentVolumeClaim ################"
  run "kubectl apply -f $M/pvc.yaml"
  for i in $(seq 30); do [ "$($N get pvc web-data -o jsonpath='{.status.phase}')" = Bound ] && break; sleep 2; done
  run "$N get pvc"
  run "kubectl get storageclass"
  echo "################ 5.3 Deployment + Service ################"
  run "kubectl apply -f $M/deployment.yaml -f $M/service.yaml"
  run "$N rollout status deploy/web-app --timeout=240s"
  run "$N get pods -o wide"
  run "$N get svc web-service && $N get endpointslices -l kubernetes.io/service-name=web-service"
  P=$($N get pod -l app=web-app -o jsonpath='{.items[0].metadata.name}')
  run "$N describe pod $P | grep -E '^    (Startup|Readiness|Liveness):|Requests:|Limits:|cpu:|memory:|/data from'"
  echo "################ 5.4 HorizontalPodAutoscaler ################"
  run "kubectl apply -f $M/hpa.yaml"
  echo "# waiting for metrics-server to report CPU for the Pods..."
  for i in $(seq 40); do $N get hpa web-app-hpa --no-headers | grep -q 'cpu: [0-9]' && break; sleep 5; done
  run "$N get hpa"
  run "$N top pods"

  echo "################ Task 1: storage persistence ################"
  run "$N exec $P -- sh -c 'echo \"Student: Milap Kothari\" > /data/student.txt'"
  run "$N exec $P -- cat /data/student.txt"
  P2=$($N get pod -l app=web-app -o jsonpath='{.items[1].metadata.name}')
  run "$N exec $P2 -- cat /data/student.txt   # the 2nd replica mounts the same PVC (RWO = one NODE; minikube has one)"
  run "$N delete pod $P"
  $N rollout status deploy/web-app --timeout=180s >/dev/null; $N wait --for=condition=Ready pod -l app=web-app --timeout=180s >/dev/null
  run "$N get pods"
  NEW=$($N get pod -l app=web-app -o jsonpath='{.items[0].metadata.name}')
  run "$N exec $NEW -- cat /data/student.txt"
  run "kubectl get pv \$($N get pvc web-data -o jsonpath='{.spec.volumeName}') -o custom-columns=PV:.metadata.name,CAPACITY:.spec.capacity.storage,RECLAIM:.spec.persistentVolumeReclaimPolicy,HOSTPATH:.spec.hostPath.path"

  echo "################ Task 2: Service verification ################"
  $N port-forward svc/web-service 18080:80 >/dev/null 2>&1 & PF=$!; sleep 4
  run 'curl -s http://localhost:18080 | head -4'
  run 'curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:18080/'
  kill $PF; wait $PF 2>/dev/null

  echo "################ Bonus challenge 2: readiness gating (path /does-not-exist) ################"
  run "$N patch deploy web-app --type=json -p '[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/readinessProbe/httpGet/path\",\"value\":\"/does-not-exist\"}]'"
  sleep 35
  run "$N get pods"
  run "$N get endpoints web-service"
  run "$N get endpointslices -l kubernetes.io/service-name=web-service -o custom-columns=NAME:.metadata.name,ADDRESSES:.endpoints[*].addresses,READY:.endpoints[*].conditions.ready"
  P=$($N get pod -l app=web-app -o jsonpath='{.items[0].metadata.name}')
  run "$N events --for pod/$P | grep -i readiness | tail -2"
  echo "# revert"
  run "kubectl apply -f $M/deployment.yaml && $N rollout status deploy/web-app --timeout=240s"

  echo "################ Bonus challenge 3: liveness restart loop (path /crash) ################"
  run "$N patch deploy web-app --type=json -p '[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/livenessProbe/httpGet/path\",\"value\":\"/crash\"}]'"
  sleep 75
  run "$N get pods"
  P=$($N get pod -l app=web-app -o jsonpath='{.items[0].metadata.name}')
  run "$N events --for pod/$P | grep -iE 'liveness|Killing' | tail -3"
  echo "# revert"
  run "kubectl apply -f $M/deployment.yaml && $N rollout status deploy/web-app --timeout=240s"
  for i in $(seq 40); do $N get hpa web-app-hpa --no-headers | grep -q 'cpu: [0-9]' && break; sleep 5; done

}

minihpa() {
  M=03-mini-project; N="kubectl -n s13-mini"
  run "kubectl apply -f $M/namespace.yaml -f $M/pvc.yaml -f $M/deployment.yaml -f $M/service.yaml -f $M/hpa.yaml"
  $N rollout status deploy/web-app --timeout=240s >/dev/null
  for i in $(seq 40); do $N get hpa web-app-hpa --no-headers | grep -q 'cpu: [0-9]' && break; sleep 5; done
  echo "################ Task 3: trigger HPA scaling ################"
  run "$N get hpa"
  run "$N run load-generator --image=busybox:1.36 --restart=Never -- /bin/sh -c 'while true; do wget -q -O- http://web-service; done'"
  sample() {  # $1 = number of 20s samples
    echo "TIME    TARGETS            MIN MAX REPLICAS | per-Pod CPU (kubectl top)"
    T0=$(date +%s)
    for i in $(seq $1); do
      top=$($N top pods -l app=web-app --no-headers 2>/dev/null | awk '{printf "%s ", $2}')
      printf "t+%-5s %s   |  %s\n" "$(( $(date +%s) - T0 ))s" "$(hpaline s13-mini web-app-hpa)" "$top"
      sleep 20
    done; echo
  }
  echo "# ---- target 50% (hpa.yaml as given) ----"
  sample 8
  run "$N top pods"
  echo "# One wget loop gives each nginx Pod ~30m CPU = ~30% of its 100m request: below 50%, so the HPA correctly keeps 2 replicas."
  echo "################ Bonus challenge 1: lower the target to 30% (same load) ################"
  run "sed 's/averageUtilization: 50/averageUtilization: 30/' $M/hpa.yaml | kubectl apply -f -"
  sample 9
  run "$N get hpa"
  run "$N get pods -o wide"
  run "$N describe hpa web-app-hpa | sed -n '/^Metrics:/,/^Min replicas/p;/^Events:/,\$p'"
  echo "################ Stop the load -> scale down (default 300s stabilization window) ################"
  run "$N delete pod load-generator --now"
  T0=$(date +%s)
  for i in $(seq 18); do
    printf "t+%-5s %s\n" "$(( $(date +%s) - T0 ))s" "$(hpaline s13-mini web-app-hpa)"
    [ "$($N get deploy web-app -o jsonpath='{.spec.replicas}')" = 2 ] && [ $i -gt 2 ] && break
    sleep 30
  done; echo
  run "$N get hpa"
  run "$N describe hpa web-app-hpa | sed -n '/^Events:/,\$p'"
  run "$N get pods"
  kubectl delete ns s13-mini --wait=false >/dev/null
}

coursehpa() {
  H=03-mini-project/course-hpa; NS=s13-hpa; N="kubectl -n $NS"
  kubectl delete ns $NS --ignore-not-found --wait --timeout=180s >/dev/null 2>&1; kubectl create ns $NS >/dev/null
  echo "################ Course hpa/ files: backend + service + HPA ################"
  run "$N apply -f $H/backend-deployment.yaml -f $H/backend-service.yaml -f $H/hpa-backend.yaml"
  run "$N rollout status deploy/yatri-backend --timeout=240s"
  for i in $(seq 40); do $N get hpa yatri-backend-hpa --no-headers | grep -q 'cpu: [0-9]' && break; sleep 5; done
  run "$N get deploy,svc,hpa"
  echo "################ Run the course's load_generator.sh (unchanged) for ~3 minutes ################"
  echo "# it calls 'kubectl port-forward svc/yatri-backend-service' without -n, so it runs with a private kubeconfig copy"
  echo "# whose current namespace is $NS (the shared context is not touched)"
  KC=$(mktemp); kubectl config view --raw > $KC; KUBECONFIG=$KC kubectl config set-context --current --namespace=$NS >/dev/null
  echo "# Port 5000 on this Mac is already taken by macOS AirPlay Receiver (ControlCenter), so the script's default"
  echo "# target http://localhost:5000/healthz would hit AirPlay, not Kubernetes:"
  run 'lsof -nP -iTCP:5000 -sTCP:LISTEN | head -3'
  run 'curl -s -o /dev/null -w "HTTP %{http_code}  server: %header{server}\n" http://localhost:5000/healthz'
  echo "# -> forward 15000 instead and pass the URL as the script's 1st argument (its curl pre-check then succeeds"
  echo "#    and it skips its own port-forward)"
  KUBECONFIG=$KC kubectl port-forward svc/yatri-backend-service 15000:80 >/dev/null 2>&1 & PF=$!; sleep 4
  run 'curl -s http://localhost:15000/healthz'
  KUBECONFIG=$KC perl -e 'setpgrp(0,0); exec @ARGV' bash $H/load_generator.sh http://localhost:15000/healthz > $H/../.lg.log 2>&1 & LG=$!
  sleep 5; echo "\$ cat load_generator.sh output"; cat $H/../.lg.log; echo
  echo "TIME    TARGETS  MIN MAX REPLICAS   | per-Pod CPU (kubectl top)"
  T0=$(date +%s)
  for i in $(seq 10); do
    top=$($N top pods -l app=yatri-backend --no-headers 2>/dev/null | awk '{printf "%s ", $2}')
    printf "t+%-5s %s   |  %s\n" "$(( $(date +%s) - T0 ))s" "$(hpaline $NS yatri-backend-hpa)" "$top"
    sleep 20
  done; echo
  kill -TERM -$LG 2>/dev/null; sleep 2; kill -KILL -$LG 2>/dev/null; kill $PF 2>/dev/null; rm -f $KC $H/../.lg.log
  echo "# load generator stopped"
  run "$N get hpa"
  run "$N top pods"
  run "$N describe hpa yatri-backend-hpa | sed -n '/^Metrics:/,/^Conditions:/p;/^Events:/,\$p'"
  kubectl delete ns $NS --wait=false >/dev/null
}

parts=${1:-"volumes hpa"}
for part in $parts; do $part > output-$part.txt 2>&1; echo "== $part ($(wc -l < output-$part.txt) lines)"; done
