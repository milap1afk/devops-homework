# k8s/ — bootstrap manifests

Applied once, before the Helm chart / Argo CD Application:

```bash
kubectl apply -f k8s/namespace.yaml
kubectl -n kirana create secret generic kirana-secrets \
  --from-literal=API_KEY="$(openssl rand -hex 16)" --from-literal=POSTGRES_PASSWORD="$(openssl rand -hex 16)"
```
The application itself is deployed by the Helm chart in [`../helm/kirana`](../helm/kirana).
[`../kubernetes/`](../kubernetes) has the same resources as plain YAML (rendered from the chart).
