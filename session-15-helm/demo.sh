#!/usr/bin/env bash
# Session 15: Helm commands + rollback workflow on minikube. Usage: ./demo.sh [commands|rollback]
cd "$(dirname "$0")"
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }
NS=s15
page() {  # fetch the page through the Service from inside the cluster
  kubectl -n $NS exec curl -- curl -s http://kirana-webapp | grep -E '<p>|<h1>' | sed -E 's/<[^>]+>//g; s/^ +//'
}
tester() { kubectl -n $NS get pod curl >/dev/null 2>&1 || { kubectl -n $NS run curl --image=curlimages/curl:8.10.1 --restart=Never --command -- sleep infinity >/dev/null; kubectl -n $NS wait --for=condition=Ready pod/curl --timeout=120s >/dev/null; }; }

commands() {
  helm uninstall kirana -n $NS >/dev/null 2>&1; kubectl delete ns $NS --wait >/dev/null 2>&1; kubectl create ns $NS >/dev/null; tester
  echo "######## helm create ########"
  run 'helm create demo-chart && find demo-chart -type f | sort && rm -rf demo-chart'
  echo "# Our chart (webapp/) was made with 'helm create webapp' and then customised:"
  run 'find webapp -type f | sort'
  run 'helm lint webapp'
  run 'helm template kirana webapp --set page.version=preview | grep -E "^kind:|image:|replicas:"'
  echo "######## helm install ########"
  run "helm install kirana ./webapp -n $NS --wait --timeout 3m"
  echo "######## helm list ########"
  run "helm list -n $NS"
  run 'helm list -A'
  echo "######## helm status ########"
  run "helm status kirana -n $NS"
  echo "# Helm 4 removed 'status --show-resources'; list the release's live objects from its manifest instead:"
  run "helm get manifest kirana -n $NS | kubectl -n $NS get -f -"
  echo "######## helm get ########"
  run "helm get values kirana -n $NS"
  run "helm get values kirana -n $NS --all | sed -n '/^page:/,/^[a-z]/p'"
  run "helm get manifest kirana -n $NS | grep -E '^# Source|^kind:'"
  run "helm get notes kirana -n $NS"
  run "helm get metadata kirana -n $NS"
  run "kubectl -n $NS get deploy,svc,cm,pods -l app.kubernetes.io/instance=kirana"
  run "kubectl -n $NS exec curl -- curl -s http://kirana-webapp | grep -E '<h1>|<p>'"
  echo "######## helm upgrade ########"
  run "helm upgrade kirana ./webapp -n $NS --set replicaCount=3 --set page.version=v2 --set page.message='Upgraded with helm upgrade' --wait --timeout 3m"
  run "kubectl -n $NS get deploy kirana-webapp"
  run 'page'
  echo "######## helm history ########"
  run "helm history kirana -n $NS"
  echo "######## helm rollback ########"
  run "helm rollback kirana 1 -n $NS --wait --timeout 3m"
  run "helm history kirana -n $NS"
  run "kubectl -n $NS get deploy kirana-webapp && sleep 5"
  run 'page'
  echo "######## helm repo ########"
  run 'helm repo add bitnami https://charts.bitnami.com/bitnami'
  run 'helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx'
  run 'helm repo update'
  run 'helm repo list'
  echo "######## helm search ########"
  run 'helm search repo nginx | head -6'
  run 'helm search repo ingress-nginx/ingress-nginx --versions | head -4'
  run 'helm search hub prometheus --max-col-width 50 | head -5'
  run 'helm show chart bitnami/nginx | grep -E "^(name|version|appVersion|description)"'
  run 'helm show values bitnami/nginx | grep -E "^replicaCount|^  type:" | head -3'
  echo "######## helm uninstall ########"
  run "helm uninstall kirana -n $NS --wait"
  run "helm list -n $NS"
  kubectl -n $NS wait --for=delete pod -l app.kubernetes.io/instance=kirana --timeout=60s >/dev/null 2>&1
  run "kubectl -n $NS get all -l app.kubernetes.io/instance=kirana"
}

rollback() {
  helm uninstall kirana -n $NS >/dev/null 2>&1; kubectl get ns $NS >/dev/null 2>&1 || kubectl create ns $NS >/dev/null; tester; sleep 3
  echo "################ 1. INSTALL (revision 1) ################"
  run "helm install kirana ./webapp -n $NS --wait --timeout 3m"
  echo "################ 2. VERIFY ################"
  run "helm history kirana -n $NS"
  run "kubectl -n $NS get deploy kirana-webapp -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,IMAGE:.spec.template.spec.containers[0].image"
  run 'page'
  echo "################ 3. UPGRADE (revision 2): new message/colour, 3 replicas ################"
  run "helm upgrade kirana ./webapp -n $NS --reuse-values --set replicaCount=3 --set page.version=v2 --set page.color='#1565c0' --set page.message='Release v2: new blue theme' --wait --timeout 3m"
  echo "################ 4. VERIFY ################"
  run "helm history kirana -n $NS"
  run "kubectl -n $NS get deploy kirana-webapp -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,IMAGE:.spec.template.spec.containers[0].image"
  sleep 3; run 'page'
  echo "################ 5. UPGRADE AGAIN (revision 3): a BAD release (image tag does not exist) ################"
  run "helm upgrade kirana ./webapp -n $NS --reuse-values --set image.tag=9.99-does-not-exist --set page.version=v3 --wait --timeout 60s"
  echo "################ 6. VERIFY: release FAILED, new Pods cannot pull the image ################"
  run "helm history kirana -n $NS"
  run "helm status kirana -n $NS | grep -E 'STATUS|REVISION|DESCRIPTION'"
  run "kubectl -n $NS get pods -l app.kubernetes.io/instance=kirana"
  echo "# old v2 Pods keep serving during the failed rollout (RollingUpdate keeps availability):"
  run 'page'
  echo "################ 7. ROLLBACK to revision 2 ################"
  run "helm rollback kirana 2 -n $NS --wait --timeout 3m"
  echo "################ 8. VERIFY ################"
  run "helm history kirana -n $NS"
  kubectl -n $NS rollout status deploy/kirana-webapp --timeout=120s >/dev/null
  for i in $(seq 30); do n=$(kubectl -n $NS get pods -l app.kubernetes.io/instance=kirana --no-headers 2>/dev/null | grep -vc Running); [ "$n" = 0 ] && break; sleep 2; done
  run "kubectl -n $NS get pods -l app.kubernetes.io/instance=kirana"
  run "kubectl -n $NS get deploy kirana-webapp -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,IMAGE:.spec.template.spec.containers[0].image"
  run "helm get values kirana -n $NS"
  run "kubectl -n $NS get configmap kirana-webapp-page -o jsonpath='{.data.index\\.html}' | grep version"
  echo "# The ConfigMap is back to revision 2. The running Pods were NOT restarted (their template already equals"
  echo "# revision 2), so their mounted index.html follows the ConfigMap only after the kubelet re-syncs the volume"
  echo "# (can lag up to ~60s; an earlier run still served the v3 page right after the rollback). Waiting for the sync:"
  for i in $(seq 30); do page | grep -q 'version: v2' && break; sleep 4; done
  run 'page'
  echo "# Note: rollback created a NEW revision (4) that is a copy of revision 2; history is never rewritten."
}

parts=${1:-"commands rollback"}
for part in $parts; do $part > output-$part.txt 2>&1; echo "== $part ($(wc -l < output-$part.txt) lines)"; done
