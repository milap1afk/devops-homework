# Session 12: Kubernetes Ingress, ConfigMaps & Secrets

Cluster: **minikube v1.37** with the `ingress` addon (ingress-nginx). Namespace `s12`.
All output comes from [`demo.sh`](demo.sh) (`./demo.sh configmap|secret|ingress|troubleshooting`). Raw logs are in `output-*.txt`.

| Deliverable | File |
|---|---|
| ConfigMap YAML | [`01-configmap/configmap.yaml`](01-configmap/configmap.yaml), [`01-configmap/pod.yaml`](01-configmap/pod.yaml) |
| Secret YAML | [`02-secret/secret.example.yaml`](02-secret/secret.example.yaml) (placeholder only), [`02-secret/pod.yaml`](02-secret/pod.yaml) |
| Ingress YAML | [`03-ingress/apps.yaml`](03-ingress/apps.yaml), [`03-ingress/ingress.yaml`](03-ingress/ingress.yaml) |
| Troubleshooting | [`05-troubleshooting/`](05-troubleshooting), [Task 5](#task-5-troubleshooting) |

---

## Task 1: ConfigMap

A **ConfigMap** stores **non-sensitive configuration** as key/value pairs or whole files, separate from the image.
The same image can then run in dev, staging and prod with different settings.

**Create:** [`configmap.yaml`](01-configmap/configmap.yaml) holds 4 simple keys (`APP_ENV`, `APP_COLOR`, `LOG_LEVEL`,
`MAX_CONNECTIONS`) and one file-style key (`app.properties`).
```bash
kubectl apply -f 01-configmap/configmap.yaml
# imperative equivalent:
kubectl create configmap app-config --from-literal=APP_ENV=production --from-file=app.properties
```

**Inject into a Pod** ([`pod.yaml`](01-configmap/pod.yaml)), three ways:

| Method | YAML | Result in container |
|---|---|---|
| One key → env var | `env[].valueFrom.configMapKeyRef` | `ENVIRONMENT=production` |
| All keys → env vars | `envFrom[].configMapRef` | `APP_COLOR=blue`, `LOG_LEVEL=info`, … |
| Keys → files | `volumes[].configMap` + `volumeMounts` | `/etc/config/APP_COLOR`, `/etc/config/app.properties` |

**Verify inside the container:**
```bash
kubectl -n s12 exec configmap-demo -- env | grep APP_
kubectl -n s12 exec configmap-demo -- cat /etc/config/app.properties
```

![configmap](screenshots/configmap.png)

**What I observed**
- All env vars and all files were present with the right values.
- After `kubectl patch configmap app-config … APP_COLOR=green`, the **mounted file changed to `green` without restarting**
  (the kubelet syncs it, using symlinks to `..data/`), but the **env var still said `blue`**. Env vars are read only when the
  container starts, so use `kubectl rollout restart deployment/<name>` to pick up env changes.

## Task 2: Secret

A **Secret** stores **sensitive data** (passwords, tokens, keys). It works like a ConfigMap but Kubernetes treats it
more carefully: `describe` hides values, volumes are mounted on **tmpfs (RAM)**, RBAC can restrict access, and it can be encrypted at rest in etcd.

**Create (from the CLI, so the value never lives in a file):**
```bash
kubectl -n s12 create secret generic db-credentials \
  --from-literal=DB_USER=appuser --from-literal=DB_PASSWORD='Demo-P@ss-2026'
```

**Inject into a Pod** ([`pod.yaml`](02-secret/pod.yaml)) with `env[].valueFrom.secretKeyRef` and as files through
`volumes[].secret` (`defaultMode: 0400`).

**Verify:**
```bash
kubectl -n s12 exec secret-demo -- sh -c 'echo $DB_PASSWORD'
kubectl -n s12 exec secret-demo -- cat /etc/secrets/DB_PASSWORD
```

![secret](screenshots/secret.png)

**What I observed**
- `describe secret` shows only `DB_PASSWORD: 14 bytes`, not the value.
- Inside the container: `DB_USER=appuser`, `DB_PASSWORD=Demo-P@ss-2026`. The files are `-r--------` (0400) on `tmpfs`.
- **But** `kubectl get secret -o jsonpath='{.data.DB_PASSWORD}' | base64 -d` printed the password straight back.

### Why Secrets must not be committed to Git

- **base64 is encoding, not encryption.** Anyone who sees `DB_PASSWORD: RGVtby1QQHNzLTIwMjY=` can run `base64 -d` in one second (shown above).
- **Git never forgets.** A deleted secret stays in the history, every clone and every fork. Public repos get scanned by bots within minutes.
- **Too many people get access:** everyone with repo access gets production credentials, with no audit trail and no rotation.

**What to do instead:** create Secrets from the CLI or CI with values from a secret store; use **Sealed Secrets** or **SOPS**
(encrypted in Git); use the **External Secrets Operator** with AWS Secrets Manager or Vault; enable **encryption at rest**; restrict with **RBAC**;
add the files to `.gitignore` and run secret scanning (gitleaks) in CI. This repo only has [`secret.example.yaml`](02-secret/secret.example.yaml) with a `change-me` placeholder.

> The demo password `Demo-P@ss-2026` is a throwaway value used only in this local minikube lab.

## Task 3: Ingress

**Deploy apps + Services:** [`apps.yaml`](03-ingress/apps.yaml) creates two Deployments (`shop`, `blog`, 2 Pods each)
with ClusterIP Services `shop-svc` and `blog-svc`.

**Configure Ingress:** [`ingress.yaml`](03-ingress/ingress.yaml) has `ingressClassName: nginx` and routes by **path** and **host**:

| Request | Routed to |
|---|---|
| `http://kirana.local/shop` | `shop-svc` |
| `http://kirana.local/blog` | `blog-svc` |
| `http://blog.kirana.local/` | `blog-svc` |
| anything else | controller default backend → **404** |

```bash
kubectl apply -f 03-ingress/apps.yaml -f 03-ingress/ingress.yaml
kubectl -n s12 get ingress demo-ingress            # ADDRESS 192.168.49.2
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8085:80 &
curl --resolve kirana.local:8085:127.0.0.1 http://kirana.local:8085/shop
```

![ingress](screenshots/ingress.png)

**What I observed (routing verified)**
- `/shop` → `SHOP service (pod shop-…)`, `/blog` → `BLOG service (pod blog-…)`, and host `blog.kirana.local` → BLOG. It worked from inside
  the node (node IP, port 80) and from the Mac (port-forward). Requests were also **load-balanced** across both Pods of each app.
- `/unknown` and the unknown host `other.local` → **HTTP 404** from the controller's default backend.
- The ingress-nginx access log shows each request with its upstream: `[s12-shop-svc-80]` / `[s12-blog-svc-80]` and the Pod IP that served it.
- `--resolve` stands in for a DNS / `/etc/hosts` entry, because the controller routes on the `Host` header.

## Task 4: Ingress vs Ingress Controller

### What is Ingress?
An **Ingress** is a Kubernetes **API object (YAML)** that *declares* HTTP/HTTPS routing rules: "requests for host X and path Y
go to Service Z", plus TLS certificates. It's only configuration. **On its own, it does nothing.**

### What is an Ingress Controller?
An **Ingress Controller** is a **running program** (Pods + a Service, usually type LoadBalancer or NodePort) that **watches** Ingress
objects through the API and **configures a real reverse proxy / load balancer** to implement them. Here it's `ingress-nginx-controller` in namespace
`ingress-nginx`, which turns our Ingress into nginx config.

### Differences

| | Ingress | Ingress Controller |
|---|---|---|
| Kind | API resource (`networking.k8s.io/v1`, `kind: Ingress`) | Deployment/DaemonSet + Service (software) |
| Role | **What** to route: rules, hosts, paths, TLS | **How** to route: actually receives and proxies traffic |
| Created by | App developer, per app (`kubectl apply -f ingress.yaml`) | Cluster admin, once per cluster (Helm chart / addon) |
| Built in? | Yes, part of Kubernetes | **No**, must be installed (minikube: `minikube addons enable ingress`) |
| Count | Many Ingress objects | Usually one or a few controllers, selected by `ingressClassName` |
| Without the other | Ingress stays inert (no ADDRESS, nothing listens) | Controller runs but routes nothing (all 404) |

### Why both are required
Kubernetes separates **intent** from **implementation**. The Ingress gives a portable, vendor-neutral way to describe
routing, and the controller is the pluggable engine that does it. You can swap NGINX for Traefik, or for an AWS ALB, without rewriting app manifests.
One controller (one external IP or cloud load balancer) serves **many** apps through many Ingress objects, which is much cheaper than one
`LoadBalancer` Service per app.

```text
Internet ─► Cloud LB / NodePort ─► [ Ingress Controller Pod (nginx) ] ─► shop-svc ─► shop Pods
                                     ▲ watches + reloads config      └─► blog-svc ─► blog Pods
                                     │
                         Ingress objects (rules) in the API server
```

### Examples
- **Ingress controllers:** ingress-nginx (used here), Traefik, HAProxy, Contour/Envoy, Kong, Istio gateway, **AWS Load Balancer Controller** (ALB), GKE Ingress, Azure Application Gateway.
- **Ingress objects:** [`ingress.yaml`](03-ingress/ingress.yaml) (path- and host-based routing); a TLS Ingress with `spec.tls: [{hosts: [kirana.local], secretName: kirana-tls}]`;
  canary routing with `nginx.ingress.kubernetes.io/canary-weight: "10"`.
- **Next generation:** the **Gateway API** (`Gateway`, `HTTPRoute`) is the successor to Ingress, with the same intent/implementation split and more features.

## Task 5: Troubleshooting

Course scenario: `troubleshooting/secret-base64-gotcha.md` from the session-12 course folder, **"The Trailing Newline Secret Bug"**:
the app's PostgreSQL login fails with `password authentication failed for user "yatri_admin"`, although the developer says
*"I verified the password is correct, I typed `echo "mypassword" | base64`"*.

I reproduced it for real in namespace `s12-ts` with the course's `yatri` names (user `yatri_admin`, password `secretpassword`, db `yatri_production_db`):

| File | What it is |
|---|---|
| [`05-troubleshooting/postgres.yaml`](05-troubleshooting/postgres.yaml) | PostgreSQL 17 (`postgres:17-alpine`, arm64) + Service. Its password comes from a Secret written with `stringData` (no hand-made base64), so the **server is correct** |
| [`05-troubleshooting/app.yaml`](05-troubleshooting/app.yaml) | the "backend": every 5s it logs in with `psql`, taking `POSTGRES_USER`, `POSTGRES_DB` and `PGPASSWORD` from Secret `yatri-db-secret` (`secretKeyRef`), and logs `OK` or `DB ERROR` |
| [`05-troubleshooting/broken-secret.yaml`](05-troubleshooting/broken-secret.yaml) | `yatri-db-secret` with the password encoded by `echo "secretpassword" \| base64` → `c2VjcmV0cGFzc3dvcmQK` |
| [`05-troubleshooting/fixed-secret.yaml`](05-troubleshooting/fixed-secret.yaml) | same Secret encoded with `echo -n` → `c2VjcmV0cGFzc3dvcmQ=` |

Run it: `./demo.sh troubleshooting` (full log: [`output-troubleshooting.txt`](output-troubleshooting.txt); the namespace is deleted at the end).

### 1. Identify the problem

![before](screenshots/troubleshooting-before.png)

The tricky part: **nothing looks broken in Kubernetes**. Both Pods are `1/1 Running` with 0 restarts. Only the app log shows it:
```text
$ kubectl -n s12-ts get pods
NAME                              READY   STATUS    RESTARTS   AGE
yatri-backend-dc88cb79b-d67mc     1/1     Running   0          24s
yatri-postgres-85d589f87f-fpqpz   1/1     Running   0          2m18s

$ kubectl -n s12-ts logs deploy/yatri-backend --tail=3
09:08:05 DB ERROR: psql: error: connection to server at "yatri-postgres" (10.101.90.92), port 5432 failed: FATAL:  password authentication failed for user "yatri_admin"
```

### 2. Troubleshooting commands (and what each one proved)

| Command | Result | Conclusion |
|---|---|---|
| `kubectl logs deploy/yatri-postgres` | `FATAL: password authentication failed for user "yatri_admin"` / `Connection matched … "host all all all scram-sha-256"` | the connection **reached** Postgres: Service, DNS and networking are fine; the user exists; only the password is wrong |
| `kubectl get deploy yatri-backend -o jsonpath='{…env…secretKeyRef}'` | `PGPASSWORD <- yatri-db-secret/POSTGRES_PASSWORD` | which Secret and key to inspect |
| `kubectl describe secret yatri-db-secret` | **`POSTGRES_PASSWORD: 15 bytes`** | `secretpassword` has 14 characters, so there's one byte too many |
| `kubectl get secret … -o jsonpath='{.data.POSTGRES_PASSWORD}' \| base64 -d \| xxd` | `7365 6372 6574 7061 7373 776f 7264 `**`0a`** | the extra byte is `0x0a` = `\n` |
| the same for the server's Secret `postgres-server-secret` | `… 776f 7264` (no `0a`) | the server was created with the real 14-character password |
| `kubectl exec deploy/yatri-backend -- sh -c 'echo ${#PGPASSWORD}'` | `15` | the container really received the newline |
| `echo "secretpassword" \| base64` vs `echo -n "secretpassword" \| base64` | `c2VjcmV0cGFzc3dvcmQK` vs `c2VjcmV0cGFzc3dvcmQ=` | reproduces exactly the value stored in the broken Secret |

### 3. Root cause

The password was base64-encoded with **`echo "secretpassword" | base64`**. `echo` appends a newline, so the Secret stored
`secretpassword\n` (15 bytes). Kubernetes decodes Secrets byte-for-byte and passes them on unchanged, so the app sent `secretpassword\n`,
and PostgreSQL correctly rejected it. Hint for next time: a base64 value ending in **`K`**, **`Cg==`** or **`o=`** usually means a trailing newline.

### 4. Fix

![after](screenshots/troubleshooting-after.png)

1. Re-encode with `echo -n` ([`fixed-secret.yaml`](05-troubleshooting/fixed-secret.yaml)) and `kubectl apply` it → `describe secret` now shows `POSTGRES_PASSWORD: 14 bytes`.
2. **The app was still failing 10 seconds later** (`09:08:29 DB ERROR …`). Values injected as **env vars are copied only when the container starts**,
   so updating a Secret doesn't change running Pods (the same behaviour as the ConfigMap env var in Task 1).
3. `kubectl rollout restart deploy/yatri-backend` → new Pod with the corrected env.

A safer way to avoid the bug entirely is to never base64 by hand:
```bash
kubectl -n s12-ts create secret generic yatri-db-secret \
  --from-literal=POSTGRES_USER=yatri_admin --from-literal=POSTGRES_PASSWORD=secretpassword \
  --from-literal=POSTGRES_DB=yatri_production_db --dry-run=client -o yaml | kubectl apply -f -
# or write the values under stringData: in the YAML (plain text, Kubernetes encodes it)
```

### 5. Before / after

| Check | Before | After |
|---|---|---|
| `describe secret` → `POSTGRES_PASSWORD` | `15 bytes` | `14 bytes` |
| `base64 -d \| xxd` | `…776f 7264 0a` | `…776f 7264` |
| `${#PGPASSWORD}` in the container | `15` | `14` |
| backend log | `DB ERROR: … password authentication failed for user "yatri_admin"` | `OK: connected to yatri_production_db as yatri_admin` |
| Postgres auth failures in the last 20s | repeating every 5s | `0` |

In the "after" `get pods`, the old backend Pod is still `Terminating`. Its PID 1 is a `sh` loop that ignores SIGTERM, so the kubelet waits for the
30s grace period before killing it. It doesn't affect the result: `logs deploy/…` already reads from the new Pod.

**Lessons:** `Running` doesn't mean "working", so read the application and server logs. `describe secret` byte counts are a quick and safe way to check a Secret
without printing it. And after changing a Secret or ConfigMap that's used as env vars, restart the workload.
