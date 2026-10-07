# Session 14: Kubernetes Troubleshooting

Cluster: **minikube v1.37**, namespace `s14`. Every scenario has a [`broken.yaml`](scenarios) that reproduces a real failure
and a `fixed.yaml`. [`demo.sh`](demo.sh) applies the broken version, investigates, fixes and verifies
(`./demo.sh commands` or `./demo.sh 01` … `09`). Each run's full output is in `output-<n>.txt`.

**The method used for every issue:** 1) Identify → 2) Investigate → 3) Root cause → 4) Fix → 5) Verify → 6) Document.

```text
kubectl get pods            → what STATUS / READY / RESTARTS?
kubectl describe pod <p>    → State, Last State, Exit Code, Conditions, *Events*
kubectl logs <p> [--previous]  → what did the app say before dying?
kubectl events --for pod/<p>   → scheduler / kubelet messages
kubectl exec / debug        → look from inside (DNS, ports, files)
kubectl get svc,endpointslices → is traffic wired to the Pods?
```

---

## Task 1: Kubernetes troubleshooting commands

![commands](screenshots/commands.png)

| Command | Purpose | Example used |
|---|---|---|
| **`kubectl get`** | list resources, filter by label or field, choose output | `kubectl get pods -A --field-selector=status.phase!=Running`, `-o jsonpath='{.status.podIP}'` |
| **`kubectl get -o wide`** | extra columns: Pod IP, node, images, selector | `kubectl -n s14 get pods -o wide` |
| **`kubectl describe`** | full object detail + **Events**, the first stop for any problem | `kubectl describe pod <p>` (State, Conditions, Events) |
| **`kubectl logs`** | container stdout/stderr | `logs <p> --tail=5`, `logs deploy/demo --timestamps`, `logs -l app=demo --prefix`, `--previous`, `-f`, `-c` |
| **`kubectl exec`** | run a command inside a container | `exec <p> -- nginx -v`, `exec <p> -- cat /etc/resolv.conf` |
| **`kubectl events`** | events, newest last, filterable | `kubectl events --for deployment/demo`, `kubectl events -A --types=Warning` |
| **`kubectl explain`** | API field documentation from the cluster | `kubectl explain pod.spec.containers.livenessProbe` |
| **`kubectl top`** | live CPU/memory (metrics-server) | `kubectl top nodes`, `top pods -A --sort-by=memory`, `top pod <p> --containers` |
| `kubectl debug` (bonus) | attach an **ephemeral debug container** with tools to a running Pod | `kubectl debug <p> --image=nicolaka/netshoot --target=<container> -- ss -ltnp` |

Full output: [`output-commands.txt`](output-commands.txt)

---

## Task 2: Troubleshoot common issues

| # | Issue | Symptom | Root cause | Fix |
|---|---|---|---|---|
| 1 | CrashLoopBackOff | `Error`, restarts climbing | required env `DB_HOST` missing, app exits 1 | add the env var |
| 2 | ImagePullBackOff | `ImagePullBackOff` | image repo doesn't exist / is private | correct image (or `imagePullSecrets`) |
| 3 | ErrImagePull | `ErrImagePull` | typo in tag `1.27-alpnie` | fix the tag |
| 4 | Pending | `Pending`, no node, no IP | `nodeSelector disktype=ssd` matches no node + 32Gi memory request | label the node, realistic request |
| 5 | ContainerCreating | stuck in `ContainerCreating` | mounted ConfigMap doesn't exist (`FailedMount`) | create the ConfigMap |
| 6 | Service connectivity | `curl http://cart` fails | Service selector typo (`carts`) → no endpoints; wrong `targetPort` | fix selector + targetPort |
| 7 | DNS | `ERROR calling http://inventory` | Service in another namespace, short name → `NXDOMAIN` | use the FQDN |
| 8 | Pod networking | Pod Running, but connections refused | app bound to `127.0.0.1`, not `0.0.0.0` | listen on all interfaces |
| 9 | Configuration | `CreateContainerConfigError` | `secretKeyRef` key `smtp_password` not in Secret | reference the correct key |

### 1. CrashLoopBackOff: [`scenarios/01-crashloopbackoff`](scenarios/01-crashloopbackoff)
![01](screenshots/01-crashloopbackoff.png)

- **Problem statement:** the `orders` Deployment never becomes Ready.
- **Investigation:**
  `kubectl get pods` → `0/1 Error  3 (31s ago)` (restarts keep climbing).
  `kubectl describe pod` → `State: Terminated  Reason: Error  Exit Code: 1`, and `Last State` shows the same.
  `kubectl logs <pod>` → **`FATAL: DB_HOST is not set`**. Events → `Warning BackOff  Back-off restarting failed container`.
- **Root cause:** the app needs env var `DB_HOST`, exits with code 1 without it, and `restartPolicy: Always` makes the kubelet restart it with growing back-off (10s, 20s, 40s … up to 5 min).
- **Solution:** add `env: DB_HOST=mysql.s14.svc.cluster.local` ([`fixed.yaml`](scenarios/01-crashloopbackoff/fixed.yaml)).
- **Before → after:** `0/1 Error 3 restarts` → `1/1 Running 0`; log `connected to mysql.s14.svc.cluster.local`.
- Tip: when the container is running again between crashes, `kubectl logs --previous` shows the crashed instance's output.

### 2. ImagePullBackOff: [`scenarios/02-imagepullbackoff`](scenarios/02-imagepullbackoff)
![02](screenshots/02-imagepullbackoff.png)

- **Problem:** the `catalog` Pod never starts.
- **Investigation:** `get pods` → `ImagePullBackOff`. `kubectl events --for pod/<p>` →
  `Failed to pull image "docker.io/milap1afk/kirana-catalog-private:1.0" … pull access denied / repository does not exist` → `Error: ErrImagePull` → `Back-off pulling image` → `Error: ImagePullBackOff`.
  `docker manifest inspect` of that image also fails.
- **Root cause:** the image repository doesn't exist, or is private and the Pod has no `imagePullSecrets`.
- **Solution:** use an image that exists ([`fixed.yaml`](scenarios/02-imagepullbackoff/fixed.yaml)). For a real private registry:
  `kubectl create secret docker-registry regcred --docker-server=… --docker-username=… --docker-password=…`, then add `imagePullSecrets: [{name: regcred}]`.
- **Before → after:** `0/1 ImagePullBackOff` → `1/1 Running`.

### 3. ErrImagePull: [`scenarios/03-errimagepull`](scenarios/03-errimagepull)
![03](screenshots/03-errimagepull.png)

- **Problem:** the `web-typo` Pod shows `ErrImagePull`.
- **Investigation:** events → `Failed to pull image "nginx:1.27-alpnie": rpc error: code = NotFound … failed to resolve reference`.
  The image field shows the typo, while `docker manifest inspect nginx:1.27-alpine` exists.
- **Root cause:** a typo in the tag (`alpnie`). **ErrImagePull** is the first failed pull. After repeated failures, the kubelet waits longer between tries and the status becomes **ImagePullBackOff**.
- **Solution:** `kubectl set image pod/web-typo web=nginx:1.27-alpine` (a Pod's image is one of the few fields editable in place).
- **Before → after:** `ErrImagePull` → `1/1 Running`, with events `Pulled` / `Started`.

### 4. Pending: [`scenarios/04-pending`](scenarios/04-pending)
![04](screenshots/04-pending.png)

- **Problem:** the `reports` Pod stays `Pending`, with `NODE <none>` and `IP <none>`.
- **Investigation:** events → `FailedScheduling  0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector`.
  `kubectl get nodes --show-labels` shows no `disktype` label. `describe node` → Allocatable memory ≈ 4.8Gi, but the Pod requests **32Gi**.
- **Root cause (two):** `nodeSelector: disktype=ssd` matches no node, **and** the memory request is larger than any node. The scheduler only reports the first
  filter that fails, so fixing one problem would reveal the next one.
- **Solution:** `kubectl label node minikube disktype=ssd` and request `64Mi` ([`fixed.yaml`](scenarios/04-pending/fixed.yaml)).
- **Before → after:** `Pending  <none>` → `1/1 Running` on node `minikube` with an IP.

### 5. ContainerCreating: [`scenarios/05-containercreating`](scenarios/05-containercreating)
![05](screenshots/05-containercreating.png)

- **Problem:** the `billing` Pod is stuck in `ContainerCreating`.
- **Investigation:** events → `FailedMount  MountVolume.SetUp failed for volume "cfg" : configmap "billing-config" not found` (repeating).
  `kubectl get configmap billing-config` → `NotFound`.
- **Root cause:** the Pod mounts a ConfigMap that was never created. The kubelet can't prepare the volume, so the container is never created.
  (Other causes of a stuck `ContainerCreating`: missing Secrets, PVCs that can't attach, CNI errors, slow image pulls.)
- **Solution:** create the ConfigMap ([`fixed.yaml`](scenarios/05-containercreating/fixed.yaml)). The kubelet retries the mount automatically, so there's no need to recreate the Pod.
- **Before → after:** `ContainerCreating` → `1/1 Running`, and `cat /etc/billing/tax_rate` → `0.18`.

### 6. Service connectivity: [`scenarios/06-service-connectivity`](scenarios/06-service-connectivity)
![06](screenshots/06-service-connectivity.png)

- **Problem:** other Pods can't reach `http://cart` (`curl` exit 7: connection failed).
- **Investigation:**
  `kubectl get endpointslices -l kubernetes.io/service-name=cart` → **`ENDPOINTS <unset>`** (no Pods behind the Service).
  `kubectl get svc cart -o wide` → `SELECTOR app=carts`, but the Pods are labelled `app=cart` (`get pods -l app=carts` → no resources).
  `curl <podIP>:5678` → `cart service OK` (the Pod is healthy), and `curl <podIP>:8080` → refused.
- **Root cause (two):** a selector typo means no endpoints, **and** `targetPort: 8080` while the container listens on `5678`.
- **Solution:** `selector: {app: cart}` and `targetPort: 5678` ([`fixed.yaml`](scenarios/06-service-connectivity/fixed.yaml)).
- **Before → after:** endpoints `<unset>` → `10.244.0.238, 10.244.0.239` (port 5678), and `curl http://cart` → `cart service OK`.

### 7. DNS issues: [`scenarios/07-dns`](scenarios/07-dns)
![07](screenshots/07-dns.png)

- **Problem:** `storefront` logs `ERROR calling http://inventory`.
- **Investigation:** `nslookup inventory` → `** server can't find inventory: NXDOMAIN`. `/etc/resolv.conf` → `search s14.svc.cluster.local …`.
  `kubectl get svc -A` shows `inventory` lives in **`s14-backend`**. `nslookup inventory.s14-backend.svc.cluster.local` → resolves. The CoreDNS Pods are `Running`.
- **Root cause:** a short name is expanded with the **client's** namespace (`inventory.s14.svc.cluster.local`), which doesn't exist. CoreDNS is fine; the name is wrong.
- **Solution:** `INVENTORY_URL=http://inventory.s14-backend.svc.cluster.local` ([`fixed.yaml`](scenarios/07-dns/fixed.yaml)). Pod env can't be edited in place, so the Pod is recreated.
- **Before → after:** `ERROR calling http://inventory` → `inventory OK`.
- More DNS checks: [Session 11 CoreDNS troubleshooting](../session-11-k8s-services/coredns/README.md#how-to-troubleshoot-dns-issues).

### 8. Pod networking issues: [`scenarios/08-pod-networking`](scenarios/08-pod-networking)
![08](screenshots/08-pod-networking.png)

- **Problem:** the `payments` Pod is `1/1 Running`, but `curl <podIP>:5678` from another Pod fails.
- **Investigation:** `ping <podIP>` → `0% packet loss`, so Pod-to-Pod routing (CNI) works.
  An ephemeral debug container: `kubectl debug payments --image=nicolaka/netshoot --target=payments -- ss -ltnp` →
  **`LISTEN 127.0.0.1:5678 users:(("http-echo",pid=1))`**.
- **Root cause:** the app listens on the **loopback** address inside the Pod's network namespace, so only processes in that Pod can connect.
  It's a classic "works in `exec`, fails from outside" bug, and the same thing happens with Flask/Node apps bound to `localhost`.
- **Solution:** bind to all interfaces (`-listen=:5678`, i.e. `0.0.0.0`) ([`fixed.yaml`](scenarios/08-pod-networking/fixed.yaml)).
- **Before → after:** `connection failed` → `payments OK`.
- Other Pod-networking checks: NetworkPolicies (`kubectl get networkpolicy -A`), CNI Pods healthy (`kubectl -n kube-system get pods`), Pod CIDR conflicts.

### 9. Configuration issues: [`scenarios/09-configuration`](scenarios/09-configuration)
![09](screenshots/09-configuration.png)

- **Problem:** the `mailer` Pod never starts: `CreateContainerConfigError`.
- **Investigation:** events → **`Error: couldn't find key smtp_password in Secret s14/smtp`**. The Secret's keys are `['password']`.
- **Root cause:** `env.valueFrom.secretKeyRef.key` points to a key that doesn't exist. (The same error happens for a missing ConfigMap key, or a missing Secret/ConfigMap used in `env`.)
- **Solution:** `secretKeyRef: {name: smtp, key: password}` ([`fixed.yaml`](scenarios/09-configuration/fixed.yaml)), or add the key to the Secret. Mark optional references with `optional: true`.
- **Before → after:** `0/1 CreateContainerConfigError` → `1/1 Running`, with `SMTP_PASSWORD is set: yes` (value not printed).

---

## Quick reference: STATUS → where to look

| STATUS | Look at | Usual causes |
|---|---|---|
| `Pending` | `describe` Events (`FailedScheduling`) | resources, nodeSelector/affinity, taints, unbound PVC |
| `ContainerCreating` | Events (`FailedMount`, CNI) | missing ConfigMap/Secret/PVC, volume attach, network plugin |
| `ErrImagePull` / `ImagePullBackOff` | Events (`Failed to pull`) | wrong name/tag, private registry, rate limits |
| `CreateContainerConfigError` | Events | missing ConfigMap/Secret or key |
| `CrashLoopBackOff` / `Error` | `logs` / `logs --previous`, Exit Code | app error, bad config, missing env, failing liveness probe |
| `OOMKilled` | `describe` Last State | memory limit too low / leak |
| `Running` but `0/1` | readiness probe in `describe` | probe path/port wrong, app not ready |
| `Running` but unreachable | endpoints, `targetPort`, `ss -ltnp`, NetworkPolicy, DNS | selector mismatch, loopback bind, policy, wrong name |

## Task 3: Mini project

> ⏳ **Pending:** the Kubernetes troubleshooting mini project from the course material hasn't been provided to me yet. It will be added here once available.
