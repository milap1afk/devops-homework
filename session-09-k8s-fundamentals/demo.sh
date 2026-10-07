#!/usr/bin/env bash
# Session 9: verify the cluster, explore architecture, do the Kubernetes Basics tutorial hands-on.
# Usage: ./demo.sh [install|cluster|architecture|objects|tutorial]
cd "$(dirname "$0")"
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }

install() {
  echo "# Installed on macOS with Homebrew (Docker engine = Colima):"
  echo "\$ brew install colima docker kubectl minikube"
  echo "\$ colima start --cpu 4 --memory 5"
  echo "\$ minikube start --driver=docker --cpus=3 --memory=3500"
  echo
  run 'minikube version'
  run 'kubectl version --client'
  run 'docker version --format "Docker engine {{.Server.Version}} ({{.Server.Os}}/{{.Server.Arch}})"'
  run 'kubectl config current-context'
  run 'kubectl config get-contexts'
}

cluster() {
  run 'minikube status'
  run 'kubectl cluster-info'
  run 'kubectl get nodes -o wide'
  run 'kubectl get --raw="/readyz?verbose" | tail -6'
  run 'kubectl get componentstatuses 2>/dev/null || true'
  run 'kubectl get namespaces'
  run 'minikube addons list | sed "s/\x1b\\[[0-9;]*m//g" | grep -E "enabled|ADDON NAME"'
}

architecture() {
  echo "# Control plane components run as static Pods in kube-system:"
  run 'kubectl get pods -n kube-system -o wide'
  run 'minikube ssh -- ls /etc/kubernetes/manifests'
  run "kubectl describe node minikube | sed -n '/^Capacity:/,/^System Info:/p' | head -16"
  run "kubectl describe node minikube | sed -n '/^System Info:/,/^PodCIDR/p'"
  echo "# Node components: kubelet (systemd service) + container runtime + kube-proxy"
  run "minikube ssh -- 'systemctl is-active kubelet; sudo crictl --version; sudo crictl ps --name kube-proxy -q | head -1 | cut -c1-12'"
  run 'kubectl api-resources --api-group=apps'
  run 'kubectl get --raw /version'
}

objects() {
  kubectl delete ns basics --ignore-not-found --wait >/dev/null 2>&1
  run 'kubectl create namespace basics'
  run 'kubectl run hello-pod -n basics --image=nginx:1.27 --labels=app=hello'
  run 'kubectl wait -n basics --for=condition=Ready pod/hello-pod --timeout=120s'
  run 'kubectl get pods -n basics --show-labels'
  run 'kubectl create deployment hello-deploy -n basics --image=nginx:1.27 --replicas=2'
  run 'kubectl rollout status -n basics deploy/hello-deploy'
  run 'kubectl get deploy,rs,pods -n basics'
  run 'kubectl expose deployment hello-deploy -n basics --port=80'
  run 'kubectl create configmap hello-config -n basics --from-literal=GREETING=namaste'
  run 'kubectl get all,cm -n basics'
  run 'kubectl explain deployment.spec.replicas'
  run 'kubectl get pod hello-pod -n basics -o yaml | head -20'
  run 'kubectl delete ns basics'
}

tutorial() {
  kubectl delete deploy kubernetes-bootcamp --ignore-not-found >/dev/null 2>&1; kubectl delete svc kubernetes-bootcamp --ignore-not-found >/dev/null 2>&1
  echo "# NOTE: the tutorial's image gcr.io/k8s-minikube/kubernetes-bootcamp:v1 is no longer available (gcr.io was shut down)"
  echo "# and docker.io/jocatalin/kubernetes-bootcamp:v2 is amd64-only. An equivalent app was rebuilt from bootcamp-app/"
  echo "# (same output, port 8080) and loaded into minikube:  docker build --build-arg VERSION=1 -t kubernetes-bootcamp:v1 bootcamp-app && minikube image load kubernetes-bootcamp:v1"
  echo
  echo "######## Module 2: Create a Deployment ########"
  run 'kubectl create deployment kubernetes-bootcamp --image=kubernetes-bootcamp:v1'
  run 'kubectl rollout status deploy/kubernetes-bootcamp --timeout=180s'
  run 'kubectl get deployments'
  echo "######## Module 3: Explore the app (Pods & Nodes) ########"
  POD=$(kubectl get pods -l app=kubernetes-bootcamp -o jsonpath='{.items[0].metadata.name}')
  run 'kubectl get pods -o wide'
  run "kubectl describe pod $POD | sed -n '1,/^Conditions:/p' | grep -E '^(Name|Namespace|Node|Status|IP|Controlled By|    Image:|    Port:)'"
  run "kubectl logs $POD"
  run "kubectl exec $POD -- env | grep -E 'HOSTNAME|KUBERNETES_SERVICE_HOST'"
  run "kubectl exec $POD -- curl -s http://localhost:8080"
  echo "######## Module 4: Expose the app publicly (Service) ########"
  run 'kubectl expose deployment/kubernetes-bootcamp --type=NodePort --port 8080'
  run 'kubectl get services'
  run 'kubectl describe services/kubernetes-bootcamp | grep -E "^(Name|Type|IP:|Port|NodePort|Endpoints)"'
  NODE_PORT=$(kubectl get services/kubernetes-bootcamp -o go-template='{{(index .spec.ports 0).nodePort}}')
  run "echo NODE_PORT=$NODE_PORT"
  run "minikube ssh -- curl -s http://\$(minikube ip):$NODE_PORT"
  echo "# Labels: query and add"
  run 'kubectl get pods -l app=kubernetes-bootcamp'
  run "kubectl label pods $POD version=v1 && kubectl get pods -l version=v1"
  echo "######## Module 5: Scale the app ########"
  run 'kubectl scale deployments/kubernetes-bootcamp --replicas=4'
  run 'kubectl rollout status deploy/kubernetes-bootcamp --timeout=180s'
  run 'kubectl get deployments'
  run 'kubectl get pods -o wide -l app=kubernetes-bootcamp'
  sleep 5
  echo "# Load balancing: requests reach different Pods"
  run "for i in 1 2 3 4 5 6; do minikube ssh -- curl -s http://\$(minikube ip):$NODE_PORT; done"
  run 'kubectl scale deployments/kubernetes-bootcamp --replicas=2 && sleep 5 && kubectl get pods -l app=kubernetes-bootcamp'
  echo "######## Module 6: Rolling update ########"
  run 'kubectl set image deployments/kubernetes-bootcamp kubernetes-bootcamp=kubernetes-bootcamp:v2'
  run 'kubectl rollout status deployments/kubernetes-bootcamp --timeout=180s'
  run "kubectl get pods -l app=kubernetes-bootcamp -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image"
  sleep 5
  run "minikube ssh -- curl -s http://\$(minikube ip):$NODE_PORT"
  echo "# Bad update (tag v10 does not exist) -> rollout stuck -> roll back"
  run 'kubectl set image deployments/kubernetes-bootcamp kubernetes-bootcamp=kubernetes-bootcamp:v10'
  sleep 25
  run 'kubectl get pods -l app=kubernetes-bootcamp'
  run 'kubectl rollout undo deployments/kubernetes-bootcamp'
  run 'kubectl rollout status deployments/kubernetes-bootcamp --timeout=180s'
  kubectl wait --for=delete pod -l pod-template-hash=$(kubectl get rs -l app=kubernetes-bootcamp -o jsonpath='{.items[?(@.spec.template.spec.containers[0].image=="kubernetes-bootcamp:v10")].metadata.labels.pod-template-hash}') --timeout=60s >/dev/null 2>&1
  run "kubectl get pods -l app=kubernetes-bootcamp -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image,STATUS:.status.phase"
  run 'kubectl rollout history deployments/kubernetes-bootcamp'
  echo "# Clean up"
  run 'kubectl delete service kubernetes-bootcamp && kubectl delete deployment kubernetes-bootcamp'
}

parts=${1:-"install cluster architecture objects tutorial"}
for p in $parts; do $p > output-$p.txt 2>&1; echo "== $p ($(wc -l < output-$p.txt) lines)"; done
