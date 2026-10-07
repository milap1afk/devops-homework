#!/usr/bin/env bash
# Session 13 demo on minikube. Usage: ./demo.sh [volumes|hpa]
cd "$(dirname "$0")"
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }
kubectl get ns s13 >/dev/null 2>&1 || kubectl create ns s13 >/dev/null
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

parts=${1:-"volumes hpa"}
for part in $parts; do $part > output-$part.txt 2>&1; echo "== $part ($(wc -l < output-$part.txt) lines)"; done
