#!/usr/bin/env bash
# Deploy (or upgrade) Kirana on minikube with Helm, using the images CI built, scanned and pushed to GHCR.
#   scripts/deploy-minikube.sh            -> the commit currently checked out (must have a green pipeline)
#   scripts/deploy-minikube.sh <git-sha>  -> any earlier release (also how you roll forward/back by commit)
# Needs: kube-prometheus-stack in "monitoring" (for the ServiceMonitor / PrometheusRule / dashboard CRDs)
#        and the Secret kirana-secrets in "kirana" (see k8s/README.md). No secret values are passed here.
set -euo pipefail
cd "$(dirname "$0")/.."
SHA=${1:-$(git rev-parse HEAD)}
echo "Deploying ghcr.io/milap1afk/kirana-{backend,frontend}:$SHA"
kubectl apply -f k8s/namespace.yaml
helm upgrade --install kirana helm/kirana -n kirana -f helm/kirana/values-minikube.yaml \
  --set backend.image.tag="$SHA" --set frontend.image.tag="$SHA" \
  --set backend.image.pullPolicy=IfNotPresent --set frontend.image.pullPolicy=IfNotPresent \
  --wait --timeout 8m
helm list -n kirana
kubectl -n kirana get pods -o wide
