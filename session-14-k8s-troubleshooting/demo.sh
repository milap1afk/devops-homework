#!/usr/bin/env bash
# Session 14 troubleshooting lab on minikube. Usage: ./demo.sh [commands|01|02|...|09|mini]
cd "$(dirname "$0")"
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }
say() { echo "# $*"; }
S=scenarios
ns() { kubectl get ns s14 >/dev/null 2>&1 || kubectl create ns s14 >/dev/null; }
tester() { kubectl -n s14 get pod netshoot >/dev/null 2>&1 || { kubectl -n s14 run netshoot --image=nicolaka/netshoot:v0.13 --restart=Never --command -- sleep infinity >/dev/null; kubectl -n s14 wait --for=condition=Ready pod/netshoot --timeout=180s >/dev/null; }; }

commands() {
  ns; kubectl -n s14 delete deploy demo --ignore-not-found >/dev/null
  kubectl -n s14 create deployment demo --image=nginx:1.27-alpine --replicas=2 >/dev/null; kubectl -n s14 rollout status deploy/demo --timeout=120s >/dev/null
  P=$(kubectl -n s14 get pod -l app=demo -o jsonpath='{.items[0].metadata.name}')
  say "---- kubectl get: list resources, filter by label, choose output ----"
  run 'kubectl get nodes'
  run 'kubectl -n s14 get pods'
  run 'kubectl -n s14 get pods -l app=demo --show-labels'
  run 'kubectl get pods -A --field-selector=status.phase!=Running'
  run "kubectl -n s14 get pod $P -o jsonpath='{.status.phase} {.status.podIP} {.spec.nodeName}{\"\\n\"}'"
  say "---- kubectl get -o wide: extra columns (IP, node, images) ----"
  run 'kubectl -n s14 get pods -o wide'
  run 'kubectl -n s14 get deploy demo -o wide'
  say "---- kubectl describe: full detail + Events (the #1 debugging command) ----"
  run "kubectl -n s14 describe pod $P | sed -n '1,12p;/^Conditions:/,/^Volumes:/p;/^Events:/,\$p'"
  say "---- kubectl logs: container stdout/stderr ----"
  run "kubectl -n s14 logs $P --tail=5"
  run "kubectl -n s14 logs deploy/demo --tail=2 --timestamps"
  run "kubectl -n s14 logs -l app=demo --prefix --tail=1"
  say "(also: --previous for the crashed instance, -f to follow, -c <container> for multi-container Pods)"
  say "---- kubectl exec: run commands inside the container ----"
  run "kubectl -n s14 exec $P -- nginx -v"
  run "kubectl -n s14 exec $P -- sh -c 'cat /etc/resolv.conf; wget -qO- localhost | grep -o \"<title>.*</title>\"'"
  run "kubectl -n s14 exec $P -- env | grep -E 'KUBERNETES_SERVICE_HOST|HOSTNAME'"
  say "---- kubectl events: cluster/namespace events, newest last ----"
  run 'kubectl -n s14 events --for deployment/demo'
  run 'kubectl events -A --types=Warning | tail -5'
  say "---- kubectl explain: built-in API documentation ----"
  run 'kubectl explain pod.spec.containers.livenessProbe | head -20'
  run 'kubectl explain deployment.spec.strategy.rollingUpdate.maxSurge'
  say "---- kubectl top: live CPU/memory (needs metrics-server) ----"
  run 'kubectl top nodes'
  run 'kubectl top pods -A --sort-by=memory | head -6'
  run "kubectl -n s14 top pod $P --containers"
  say "---- bonus ----"
  run 'kubectl debug -n s14 '"$P"' -it=false --image=busybox:1.36 --target=nginx -- sh -c "ps aux | head -5" 2>&1 | tail -6'
  run 'kubectl get --raw /readyz'
  kubectl -n s14 delete deploy demo >/dev/null
}

s01() {
  ns; kubectl -n s14 delete deploy orders --ignore-not-found --wait >/dev/null
  say "======== PROBLEM: the orders app never becomes Ready ========"
  run "kubectl apply -f $S/01-crashloopbackoff/broken.yaml"
  for i in $(seq 40); do r=$(kubectl -n s14 get pods -l app=orders -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}'); [ "${r:-0}" -ge 3 ] && break; sleep 5; done
  say "1. IDENTIFY"
  run 'kubectl -n s14 get pods -l app=orders'
  say "2. INVESTIGATE"
  run "kubectl -n s14 describe pod -l app=orders | grep -A6 -E '^    State:|Last State'"
  P=$(kubectl -n s14 get pod -l app=orders -o jsonpath='{.items[0].metadata.name}')
  run "kubectl -n s14 logs $P   # (use --previous when the container is currently running again)"
  run "kubectl -n s14 events --for pod/$P | tail -6"
  say "3. ROOT CAUSE: the container exits with code 1 because required env var DB_HOST is missing; restartPolicy Always -> restart loop with growing back-off"
  say "4. FIX: add DB_HOST to the Deployment"
  run "diff $S/01-crashloopbackoff/broken.yaml $S/01-crashloopbackoff/fixed.yaml"
  run "kubectl apply -f $S/01-crashloopbackoff/fixed.yaml && kubectl -n s14 rollout status deploy/orders --timeout=120s"
  kubectl -n s14 wait --for=delete pod/$P --timeout=60s >/dev/null 2>&1
  say "5. VERIFY"
  run 'kubectl -n s14 get pods -l app=orders'
  run 'kubectl -n s14 logs deploy/orders'
}

s02() {
  ns; kubectl -n s14 delete deploy catalog --ignore-not-found --wait >/dev/null
  say "======== PROBLEM: catalog Pod stuck, never starts ========"
  run "kubectl apply -f $S/02-imagepullbackoff/broken.yaml"
  for i in $(seq 30); do kubectl -n s14 get pods -l app=catalog --no-headers | grep -q ImagePullBackOff && break; sleep 3; done
  say "1. IDENTIFY"
  run 'kubectl -n s14 get pods -l app=catalog'
  say "2. INVESTIGATE"
  P=$(kubectl -n s14 get pod -l app=catalog -o jsonpath='{.items[0].metadata.name}'); run "kubectl -n s14 events --for pod/$P | tail -6"
  run "kubectl -n s14 get pod $P -o jsonpath='{.spec.containers[0].image}{\"\\n\"}{.status.containerStatuses[0].state.waiting.message}{\"\\n\"}' | cut -c1-220"
  run 'docker manifest inspect docker.io/milap1afk/kirana-catalog-private:1.0 2>&1 | head -2'
  say "3. ROOT CAUSE: the image repository does not exist (or is private without imagePullSecrets) -> pull fails -> kubelet backs off: ImagePullBackOff"
  say "4. FIX: point to an image that exists (for a private registry: create a docker-registry Secret and add imagePullSecrets)"
  run "diff $S/02-imagepullbackoff/broken.yaml $S/02-imagepullbackoff/fixed.yaml"
  run "kubectl apply -f $S/02-imagepullbackoff/fixed.yaml && kubectl -n s14 rollout status deploy/catalog --timeout=120s"
  say "5. VERIFY"
  run 'kubectl -n s14 get pods -l app=catalog'
}

s03() {
  ns; kubectl -n s14 delete pod web-typo --ignore-not-found --wait >/dev/null
  say "======== PROBLEM: web Pod shows ErrImagePull ========"
  run "kubectl apply -f $S/03-errimagepull/broken.yaml"
  for i in $(seq 30); do kubectl -n s14 get pod web-typo --no-headers | grep -qE 'ErrImagePull|ImagePullBackOff' && break; sleep 2; done
  say "1. IDENTIFY"
  run 'kubectl -n s14 get pod web-typo'
  say "2. INVESTIGATE"
  run "kubectl -n s14 events --for pod/web-typo | tail -6"
  run "kubectl -n s14 get pod web-typo -o jsonpath='{.spec.containers[0].image}{\"\\n\"}'"
  run 'docker manifest inspect nginx:1.27-alpnie 2>&1 | head -1; docker manifest inspect nginx:1.27-alpine >/dev/null && echo "nginx:1.27-alpine exists"'
  say "3. ROOT CAUSE: typo in the image tag (alpnie) -> registry returns 'not found' -> ErrImagePull (first failure) -> ImagePullBackOff (retrying)"
  say "4. FIX: correct the tag. A Pod's image can be changed in place:"
  run "kubectl -n s14 set image pod/web-typo web=nginx:1.27-alpine"
  run 'kubectl -n s14 wait --for=condition=Ready pod/web-typo --timeout=120s'
  say "5. VERIFY"
  run 'kubectl -n s14 get pod web-typo'
  run "kubectl -n s14 events --for pod/web-typo | tail -3"
}

s04() {
  ns; kubectl -n s14 delete deploy reports --ignore-not-found --wait >/dev/null; kubectl label node minikube disktype- >/dev/null 2>&1
  say "======== PROBLEM: reports Pod stays Pending ========"
  run "kubectl apply -f $S/04-pending/broken.yaml"; sleep 6
  say "1. IDENTIFY"
  run 'kubectl -n s14 get pods -l app=reports -o wide'
  say "2. INVESTIGATE"
  P=$(kubectl -n s14 get pod -l app=reports -o jsonpath='{.items[0].metadata.name}'); run "kubectl -n s14 events --for pod/$P | tail -6"
  run 'kubectl get nodes --show-labels | tr "," "\n" | grep -E "NAME|disktype|kubernetes.io/hostname" '
  run "kubectl describe node minikube | grep -A10 'Allocatable:' | grep -E '^  (cpu|memory)'"
  run "kubectl describe node minikube | sed -n '/Allocated resources/,/Events/p' | head -8"
  say "3. ROOT CAUSE (two problems): nodeSelector disktype=ssd matches no node, AND requests.memory 32Gi > node allocatable (~4.8Gi)"
  say "4. FIX: label the node (or remove the selector) and request a realistic amount of memory"
  run 'kubectl label node minikube disktype=ssd'
  run "diff $S/04-pending/broken.yaml $S/04-pending/fixed.yaml"
  run "kubectl apply -f $S/04-pending/fixed.yaml && kubectl -n s14 rollout status deploy/reports --timeout=120s"
  say "5. VERIFY"
  run 'kubectl -n s14 get pods -l app=reports -o wide'
  kubectl label node minikube disktype- >/dev/null
}

s05() {
  ns; kubectl -n s14 delete pod billing --ignore-not-found --wait >/dev/null; kubectl -n s14 delete cm billing-config --ignore-not-found >/dev/null
  say "======== PROBLEM: billing Pod stuck in ContainerCreating ========"
  run "kubectl apply -f $S/05-containercreating/broken.yaml"; sleep 15
  say "1. IDENTIFY"
  run 'kubectl -n s14 get pod billing'
  say "2. INVESTIGATE"
  run "kubectl -n s14 events --for pod/billing | tail -6"
  run 'kubectl -n s14 get configmap billing-config'
  say "3. ROOT CAUSE: the Pod mounts ConfigMap billing-config, which does not exist -> kubelet cannot set up the volume (FailedMount) -> container is never created"
  say "4. FIX: create the ConfigMap (the kubelet retries the mount automatically)"
  run "kubectl apply -f $S/05-containercreating/fixed.yaml"
  run 'kubectl -n s14 wait --for=condition=Ready pod/billing --timeout=180s'
  say "5. VERIFY"
  run 'kubectl -n s14 get pod billing'
  run 'kubectl -n s14 exec billing -- cat /etc/billing/tax_rate; echo'
}

s06() {
  ns; tester; kubectl -n s14 delete -f $S/06-service-connectivity/broken.yaml --ignore-not-found --wait >/dev/null 2>&1
  say "======== PROBLEM: other services cannot reach the cart Service ========"
  run "kubectl apply -f $S/06-service-connectivity/broken.yaml && kubectl -n s14 rollout status deploy/cart --timeout=120s"
  say "1. IDENTIFY"
  run 'kubectl -n s14 exec netshoot -- curl -s -m 3 http://cart || echo "curl failed (exit $?)"'
  say "2. INVESTIGATE"
  run 'kubectl -n s14 get svc cart -o wide'
  run 'kubectl -n s14 get endpointslices -l kubernetes.io/service-name=cart'
  run 'kubectl -n s14 get pods -l app=cart --show-labels -o wide'
  run 'kubectl -n s14 get pods -l app=carts'
  P=$(kubectl -n s14 get pod -l app=cart -o jsonpath='{.items[0].status.podIP}')
  run "kubectl -n s14 exec netshoot -- curl -s -m 3 http://$P:5678   # Pod itself is healthy on 5678"
  run "kubectl -n s14 exec netshoot -- curl -s -m 3 http://$P:8080 || echo 'nothing listens on 8080'"
  say "3. ROOT CAUSE (two problems): Service selector app=carts matches NO Pods (empty endpoints), and targetPort 8080 is wrong (container listens on 5678)"
  say "4. FIX: correct selector and targetPort"
  run "diff $S/06-service-connectivity/broken.yaml $S/06-service-connectivity/fixed.yaml"
  run "kubectl apply -f $S/06-service-connectivity/fixed.yaml"; sleep 6
  say "5. VERIFY"
  run 'kubectl -n s14 get endpointslices -l kubernetes.io/service-name=cart'
  run 'kubectl -n s14 exec netshoot -- curl -s -m 3 http://cart'
}

s07() {
  ns; tester; kubectl -n s14 delete pod storefront --ignore-not-found --wait >/dev/null
  say "======== PROBLEM: storefront logs 'ERROR calling http://inventory' ========"
  run "kubectl apply -f $S/07-dns/broken.yaml"
  kubectl -n s14-backend rollout status deploy/inventory --timeout=120s >/dev/null; kubectl -n s14 wait --for=condition=Ready pod/storefront --timeout=120s >/dev/null; sleep 8
  say "1. IDENTIFY"
  run 'kubectl -n s14 logs storefront --tail=2'
  say "2. INVESTIGATE"
  run 'kubectl -n s14 exec netshoot -- nslookup inventory 2>&1 | tail -3'
  run 'kubectl -n s14 exec netshoot -- cat /etc/resolv.conf'
  run 'kubectl get svc -A | grep -E "NAMESPACE|inventory"'
  run 'kubectl -n s14 exec netshoot -- nslookup inventory.s14-backend.svc.cluster.local | tail -2'
  run 'kubectl -n kube-system get pods -l k8s-app=kube-dns'
  say "3. ROOT CAUSE: the Service is in namespace s14-backend; the short name 'inventory' is expanded with the CLIENT's namespace (inventory.s14.svc.cluster.local) -> NXDOMAIN. CoreDNS itself is healthy."
  say "4. FIX: use the FQDN inventory.s14-backend.svc.cluster.local (Pod env cannot be edited in place -> recreate)"
  run "diff $S/07-dns/broken.yaml $S/07-dns/fixed.yaml"
  run "kubectl -n s14 delete pod storefront --wait && kubectl apply -f $S/07-dns/fixed.yaml"
  kubectl -n s14 wait --for=condition=Ready pod/storefront --timeout=120s >/dev/null; sleep 7
  say "5. VERIFY"
  run 'kubectl -n s14 logs storefront --tail=2'
}

s08() {
  ns; tester; kubectl -n s14 delete pod payments --ignore-not-found --wait >/dev/null
  say "======== PROBLEM: payments Pod is Running, but nothing can connect to it ========"
  run "kubectl apply -f $S/08-pod-networking/broken.yaml && kubectl -n s14 wait --for=condition=Ready pod/payments --timeout=120s"
  P=$(kubectl -n s14 get pod payments -o jsonpath='{.status.podIP}')
  say "1. IDENTIFY"
  run 'kubectl -n s14 get pod payments -o wide'
  run "kubectl -n s14 exec netshoot -- curl -s -m 3 http://$P:5678 || echo 'connection failed'"
  say "2. INVESTIGATE"
  run "kubectl -n s14 exec netshoot -- ping -c 2 -W 2 $P | tail -2   # L3 networking to the Pod works"
  run "kubectl debug -n s14 payments -it=false --image=nicolaka/netshoot:v0.13 --target=payments -- ss -ltnp 2>&1 | tail -3"
  sleep 4; run "kubectl -n s14 logs payments -c \$(kubectl -n s14 get pod payments -o jsonpath='{.spec.ephemeralContainers[-1].name}') | tail -3"
  say "3. ROOT CAUSE: the app listens on 127.0.0.1:5678 (loopback inside the Pod), not 0.0.0.0 -> only reachable from inside its own network namespace"
  say "4. FIX: bind to all interfaces (-listen=:5678)"
  run "diff $S/08-pod-networking/broken.yaml $S/08-pod-networking/fixed.yaml"
  run "kubectl -n s14 delete pod payments --wait && kubectl apply -f $S/08-pod-networking/fixed.yaml && kubectl -n s14 wait --for=condition=Ready pod/payments --timeout=120s"
  P=$(kubectl -n s14 get pod payments -o jsonpath='{.status.podIP}')
  say "5. VERIFY"
  run "kubectl -n s14 exec netshoot -- curl -s -m 3 http://$P:5678"
}

s09() {
  ns; kubectl -n s14 delete pod mailer --ignore-not-found --wait >/dev/null
  say "======== PROBLEM: mailer Pod never starts ========"
  run "kubectl apply -f $S/09-configuration/broken.yaml"; sleep 8
  say "1. IDENTIFY"
  run 'kubectl -n s14 get pod mailer'
  say "2. INVESTIGATE"
  run "kubectl -n s14 events --for pod/mailer | tail -6"
  run "kubectl -n s14 get secret smtp -o jsonpath='{.data}' | python3 -c 'import json,sys; print(\"keys in secret smtp:\", list(json.load(sys.stdin)))'"
  say "3. ROOT CAUSE: env SMTP_PASSWORD references key 'smtp_password', but Secret smtp only has key 'password' -> CreateContainerConfigError"
  say "4. FIX: reference the right key (or add the key to the Secret)"
  run "diff $S/09-configuration/broken.yaml $S/09-configuration/fixed.yaml"
  run "kubectl -n s14 delete pod mailer --wait && kubectl apply -f $S/09-configuration/fixed.yaml && kubectl -n s14 wait --for=condition=Ready pod/mailer --timeout=120s"
  say "5. VERIFY"
  run 'kubectl -n s14 get pod mailer'
  run 'kubectl -n s14 exec mailer -- sh -c "echo SMTP_PASSWORD is set: \${SMTP_PASSWORD:+yes}"'
}

smini() {
  MP=mini-project; NS=s14-mini; N="kubectl -n $NS"
  kubectl delete ns $NS --ignore-not-found --wait --timeout=180s >/dev/null 2>&1; kubectl create ns $NS >/dev/null
  $N run tester --image=busybox:1.36 --restart=Never --command -- sleep 3600 >/dev/null; $N wait --for=condition=Ready pod/tester --timeout=180s >/dev/null
  probe() { $N exec tester -- sh -c "$1" 2>&1; }   # a busybox "client" Pod in the same namespace
  say "================ 1. DEPLOY ================"
  run "$N apply -f $MP/deployment.yaml -f $MP/service.yaml"
  run "$N rollout status deploy/troubleshooting-app --timeout=180s"
  run "$N get pods"
  run "$N get service"
  say "================ 2. CHECK THE APPLICATION ================"
  run "$N get pods -o wide"
  P=$($N get pod -l app=troubleshooting-app -o jsonpath='{.items[0].metadata.name}')
  run "$N describe pod $P | sed -n '1,9p;/^    Image:/p;/^    State:/,/^    Ready:/p;/^Conditions:/,/^Volumes:/p;/^Events:/,\$p' | grep -v '^Volumes:'"
  run "$N logs $P --tail=4"
  run "$N exec $P -- curl -s localhost | grep -E '<title>|<h1>'   # (README: exec -it ... -- bash, then curl localhost)"
  say "================ 3-4. CHECK THE SERVICE AND ENDPOINTS ================"
  run "$N describe service troubleshooting-service | grep -E '^(Name|Selector|Type|IP|Port|TargetPort|Endpoints):'"
  run "$N get endpoints troubleshooting-service"
  run "$N get endpointslices -l kubernetes.io/service-name=troubleshooting-service"
  run "probe 'wget -qO- -T 3 http://troubleshooting-service | grep -o \"<title>.*</title>\"'"

  say "================ 5. CREATE A BROKEN POD ================"
  run "$N apply -f $MP/broken-pod.yaml"
  for i in $(seq 40); do $N get pod project-broken-pod --no-headers | grep -qE 'ImagePullBackOff' && break; sleep 3; done
  say "================ 6. TROUBLESHOOT IT (YAML not changed yet) ================"
  run "$N get pod project-broken-pod"
  run "$N describe pod project-broken-pod | sed -n '/^Containers:/,/^    Ready:/p;/^Events:/,\$p'"
  run "$N get pod project-broken-pod -o jsonpath='{.spec.containers[0].image}{\"\\n\"}{.status.containerStatuses[0].state.waiting.reason}: {.status.containerStatuses[0].state.waiting.message}{\"\\n\"}' | cut -c1-230"
  run "$N events --for pod/project-broken-pod --types=Warning"
  run 'docker manifest inspect nginx:this-tag-does-not-exist 2>&1 | head -1'
  run 'docker manifest inspect nginx:1.27 >/dev/null && echo "nginx:1.27 exists"'
  say "ROOT CAUSE: tag 'this-tag-does-not-exist' is not published for the nginx repository -> registry 'not found' -> ErrImagePull -> ImagePullBackOff"
  say "FIX: use a tag that exists. (A Pod's image can be changed in place with 'kubectl set image', but here the YAML is fixed and re-applied)"
  run "diff $MP/broken-pod.yaml $MP/fixed-pod.yaml"
  run "$N delete pod project-broken-pod --wait && $N apply -f $MP/fixed-pod.yaml"
  run "$N wait --for=condition=Ready pod/project-broken-pod --timeout=180s"
  say "VERIFY"
  run "$N get pod project-broken-pod -o wide"
  run "$N events --for pod/project-broken-pod | tail -4"

  say "================ 8. SERVICE TROUBLESHOOTING CHALLENGE: break the selector ================"
  run "diff $MP/service.yaml $MP/broken-service.yaml"
  run "$N apply -f $MP/broken-service.yaml"
  sleep 3
  run "$N get service"
  run "$N get endpoints troubleshooting-service"
  run "probe 'wget -qO- -T 3 http://troubleshooting-service || echo \"request failed (exit \$?)\"'"
  say "================ 9. FIND THE ROOT CAUSE ================"
  run "$N get pods --show-labels"
  run "$N describe service troubleshooting-service | grep -E '^(Selector|Endpoints):'"
  run "$N get pods -l app=wrong-app"
  say "ROOT CAUSE: Service selector app=wrong-app matches no Pod (Pods are labelled app=troubleshooting-app) -> no endpoints -> nothing to forward to"
  say "FIX: restore the selector"
  run "$N apply -f $MP/service.yaml"
  sleep 3
  say "VERIFY"
  run "$N describe service troubleshooting-service | grep -E '^(Selector|Endpoints):'"
  run "$N get endpoints troubleshooting-service"
  run "probe 'wget -qO- -T 3 http://troubleshooting-service | grep -o \"<title>.*</title>\"'"
  say "================ 10. FINAL CHECKLIST: events + DNS ================"
  run "$N get events --sort-by=.lastTimestamp | tail -8"
  run "probe 'nslookup troubleshooting-service; cat /etc/resolv.conf'"
  run "$N get pods -o wide"
  kubectl delete ns $NS --wait=false >/dev/null
}

parts=${1:-"commands 01 02 03 04 05 06 07 08 09 mini"}
for part in $parts; do f=$part; [ "$part" != commands ] && f=s$part; $f > output-$part.txt 2>&1; echo "== $part ($(wc -l < output-$part.txt) lines)"; done
