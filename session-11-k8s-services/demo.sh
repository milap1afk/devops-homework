#!/usr/bin/env bash
# Session 11 demo on minikube. Usage: ./demo.sh [clusterip|nodeport|loadbalancer|externalname|headless|dns|coredns]
cd "$(dirname "$0")"
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }
c() { kubectl -n s11 exec client -- "$@"; }
setup() {
  kubectl apply -f services/00-namespace-and-app.yaml >/dev/null
  kubectl -n s11 rollout status deploy/web --timeout=180s >/dev/null
  kubectl -n s11 wait --for=condition=Ready pod/client --timeout=300s >/dev/null
}
settle() { sleep 6; }   # let EndpointSlices + kube-proxy rules catch up

clusterip() {
  run 'kubectl apply -f services/01-clusterip.yaml'; settle
  run 'kubectl -n s11 get svc web-clusterip -o wide'
  run 'kubectl -n s11 get pods -l app=web -o wide'
  run 'kubectl -n s11 get endpointslices -l kubernetes.io/service-name=web-clusterip'
  run 'kubectl -n s11 describe svc web-clusterip | grep -E "^(Type|IP|Port|TargetPort|Endpoints)"'
  echo "# From inside the cluster, by DNS name -> requests are spread across the 3 Pods"
  run "kubectl -n s11 exec client -- sh -c 'for i in \$(seq 9); do curl -s http://web-clusterip; done' | sort | uniq -c"
  CIP=$(kubectl -n s11 get svc web-clusterip -o jsonpath='{.spec.clusterIP}')
  run "kubectl -n s11 exec client -- curl -s http://$CIP"
  echo "# From OUTSIDE the cluster (the Mac) the ClusterIP is not reachable:"
  run "curl -s -m 3 http://$CIP || echo 'curl: timed out -> ClusterIP is internal only'"
}

nodeport() {
  run 'kubectl apply -f services/02-nodeport.yaml'; settle
  run 'kubectl -n s11 get svc web-nodeport'
  NODE_IP=$(minikube ip)
  run 'kubectl get nodes -o wide | awk "{print \$1, \$6}"'
  echo "# NodeIP:NodePort works from anywhere that can reach the node (here: from inside the node and from a Pod)"
  run "minikube ssh -- curl -s http://$NODE_IP:30080"
  run "kubectl -n s11 exec client -- curl -s http://$NODE_IP:30080"
  echo "# The NodePort Service still has a ClusterIP too:"
  run 'kubectl -n s11 exec client -- curl -s http://web-nodeport'
  echo "# From the Mac, minikube (Docker driver) needs a forwarded URL to reach the node:"
  minikube service web-nodeport -n s11 --url > /tmp/np-url.txt 2>/dev/null & P=$!
  for i in $(seq 20); do grep -q http /tmp/np-url.txt 2>/dev/null && break; sleep 1; done
  URL=$(grep -m1 http /tmp/np-url.txt)
  run "echo $URL"
  run "curl -s $URL"
  kill $P 2>/dev/null; wait $P 2>/dev/null
}

loadbalancer() {
  run 'kubectl apply -f services/03-loadbalancer.yaml'; sleep 2
  run 'kubectl -n s11 get svc web-loadbalancer'
  echo "# EXTERNAL-IP is <pending>: there is no cloud load balancer. Start minikube tunnel (acts as the cloud LB):"
  (minikube tunnel > /tmp/tunnel.log 2>&1 &)
  for i in $(seq 60); do ip=$(kubectl -n s11 get svc web-loadbalancer -o jsonpath='{.status.loadBalancer.ingress[0].ip}'); [ -n "$ip" ] && break; sleep 1; done
  run 'kubectl -n s11 get svc web-loadbalancer'
  sleep 3
  run "for i in 1 2 3 4 5 6; do curl -s -m 3 http://$ip:8088; done | sort | uniq -c"
  run "kubectl -n s11 describe svc web-loadbalancer | grep -E '^(Type|LoadBalancer Ingress|Port|NodePort|Endpoints)'"
  pkill -f "minikube tunnel"
}

externalname() {
  run 'kubectl apply -f services/04-externalname.yaml'; sleep 2
  run 'kubectl -n s11 get svc external-api'
  echo "# DNS answers with a CNAME to the external host (no ClusterIP, no endpoints):"
  run 'kubectl -n s11 exec client -- dig +short external-api.s11.svc.cluster.local'
  run 'kubectl -n s11 exec client -- nslookup external-api | head -8'
  echo "# Call it by the in-cluster name (Host header set because the remote server routes by hostname):"
  run "kubectl -n s11 exec client -- curl -s -m 10 -H 'Host: httpbin.org' http://external-api/get | head -12 | sed -E 's/(\"origin\": \")[^\"]+/\1<my-public-ip-redacted>/'"
  run 'kubectl -n s11 get endpointslices -l kubernetes.io/service-name=external-api'
}

headless() {
  run 'kubectl apply -f services/05-headless.yaml'
  run 'kubectl -n s11 rollout status statefulset/db --timeout=180s'
  settle
  run 'kubectl -n s11 get svc db-headless'
  run 'kubectl -n s11 get pods -l app=db -o wide'
  echo "# Normal Service -> DNS returns ONE virtual IP:"
  run 'kubectl -n s11 exec client -- dig +short web-clusterip.s11.svc.cluster.local'
  echo "# Headless Service -> DNS returns EVERY Pod IP:"
  run 'kubectl -n s11 exec client -- dig +short db-headless.s11.svc.cluster.local'
  echo "# ...and each StatefulSet Pod gets its own stable DNS name:"
  run "kubectl -n s11 exec client -- sh -c 'for i in 0 1 2; do echo -n \"db-\$i -> \"; dig +short db-\$i.db-headless.s11.svc.cluster.local; done'"
  run "kubectl -n s11 exec client -- sh -c 'for i in 0 1 2; do curl -s http://db-\$i.db-headless:5678; done'"
}

dns() {
  run 'kubectl -n s11 exec client -- cat /etc/resolv.conf'
  echo "# Short name works only inside the same namespace (search list adds s11.svc.cluster.local)"
  run 'kubectl -n s11 exec client -- nslookup web-clusterip | tail -3'
  run 'kubectl -n s11 exec client -- dig +search +short web-clusterip.s11'
  run 'kubectl -n s11 exec client -- dig +search +short web-clusterip.s11.svc'
  run 'kubectl -n s11 exec client -- dig +short web-clusterip.s11.svc.cluster.local'
  echo "# A Service in ANOTHER namespace needs at least <svc>.<namespace>:"
  run 'kubectl -n s11 exec client -- dig +search +short kubernetes          # -> kubernetes.s11.svc.cluster.local: does not exist'
  run 'kubectl -n s11 exec client -- dig +search +short kubernetes.default'
  run 'kubectl -n s11 exec client -- dig +short kubernetes.default.svc.cluster.local'
  run 'kubectl -n s11 exec client -- dig +short kube-dns.kube-system.svc.cluster.local'
  echo "# SRV record (port discovery) and Pod A record (dashed IP):"
  run 'kubectl -n s11 exec client -- dig +short SRV _http._tcp.db-headless.s11.svc.cluster.local'
  PIP=$(kubectl -n s11 get pod client -o jsonpath='{.status.podIP}'); DASH=${PIP//./-}
  run "kubectl -n s11 exec client -- dig +short $DASH.s11.pod.cluster.local"
  echo "# Reverse lookup of the ClusterIP"
  CIP=$(kubectl -n s11 get svc web-clusterip -o jsonpath='{.spec.clusterIP}')
  run "kubectl -n s11 exec client -- dig +short -x $CIP"
  echo "# Pod-to-Service across namespaces: a Pod in 'default' calling the s11 Service"
  kubectl -n default delete pod dnstest --ignore-not-found >/dev/null
  run "kubectl -n default run dnstest --restart=Never --image=curlimages/curl:8.10.1 -- sh -c 'echo FQDN:; curl -s http://web-clusterip.s11.svc.cluster.local; echo SHORT NAME:; curl -s -m 3 http://web-clusterip || echo \"curl: (6) Could not resolve host: web-clusterip\"'"
  kubectl -n default wait --for=jsonpath='{.status.phase}'=Succeeded pod/dnstest --timeout=120s >/dev/null
  run 'kubectl -n default logs dnstest'
  kubectl -n default delete pod dnstest --now >/dev/null
}

coredns() {
  run 'kubectl -n kube-system get deploy coredns'
  run 'kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide'
  run 'kubectl -n kube-system get svc kube-dns'
  run 'kubectl -n kube-system get endpointslices -l kubernetes.io/service-name=kube-dns'
  run "kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}'"
  echo "# nameserver in every Pod = kube-dns ClusterIP:"
  run 'kubectl -n s11 exec client -- grep nameserver /etc/resolv.conf'
  run "kubectl get pod -n s11 client -o jsonpath='dnsPolicy={.spec.dnsPolicy}{\"\\n\"}'"
  echo "# Query CoreDNS directly, showing the full answer section"
  run 'kubectl -n s11 exec client -- dig web-clusterip.s11.svc.cluster.local +noall +answer +stats | grep -vE "^;; (WHEN|MSG)"'
  echo "# External names are forwarded upstream (forward . /etc/resolv.conf)"
  run 'kubectl -n s11 exec client -- dig +short google.com | head -2'
  echo "# The 'log' plugin (enabled in minikube's Corefile) logs every query. Make one and read CoreDNS logs:"
  run 'kubectl -n s11 exec client -- dig +short web-clusterip.s11.svc.cluster.local'
  sleep 2
  run "kubectl -n kube-system logs -l k8s-app=kube-dns --tail=200 | grep web-clusterip | tail -2"
  echo "# Troubleshooting: break DNS for one Pod and diagnose it"
  run "kubectl -n s11 run baddns --image=nicolaka/netshoot:v0.13 --restart=Never --overrides='{\"spec\":{\"dnsPolicy\":\"None\",\"dnsConfig\":{\"nameservers\":[\"10.255.255.1\"]}}}' -- sleep 300"
  kubectl -n s11 wait --for=condition=Ready pod/baddns --timeout=120s >/dev/null
  run 'kubectl -n s11 exec baddns -- nslookup -timeout=2 web-clusterip.s11.svc.cluster.local'
  run 'kubectl -n s11 exec baddns -- cat /etc/resolv.conf'
  echo "# Root cause: wrong nameserver (dnsPolicy None). Compare with a healthy Pod, then fix by recreating with default dnsPolicy"
  run 'kubectl -n s11 exec baddns -- nslookup -timeout=2 web-clusterip.s11.svc.cluster.local 10.96.0.10 | tail -2'
  run 'kubectl -n s11 delete pod baddns --now'
}

parts=${1:-"clusterip nodeport loadbalancer externalname headless dns coredns"}
setup
for p in $parts; do $p > output-$p.txt 2>&1; echo "== $p ($(wc -l < output-$p.txt) lines)"; done
