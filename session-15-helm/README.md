# Session 15: Helm

**Helm** is the package manager for Kubernetes. A **chart** is a package of templated manifests plus default
`values.yaml`. Installing a chart creates a **release**, and every install, upgrade or rollback creates a numbered **revision**, stored as a Secret in the namespace.

Tools: **Helm v4.3.0** on minikube v1.37. Everything below was run with [`demo.sh`](demo.sh)
(`./demo.sh commands|rollback`). Raw logs: [`output-commands.txt`](output-commands.txt), [`output-rollback.txt`](output-rollback.txt).

| Deliverable | Where |
|---|---|
| Helm chart | [`webapp/`](webapp) |
| values.yaml | [`webapp/values.yaml`](webapp/values.yaml) |
| Templates | [`webapp/templates/`](webapp/templates) |
| Installation / Upgrade / Rollback | [Task 1](#task-1-helm-commands), [Task 2](#task-2-helm-rollback) |
| Screenshots | [`screenshots/`](screenshots) |
| Mini project | [Task 3](#task-3-mini-project) |

## The chart: `webapp/`

Created with `helm create webapp`, then customised. It's nginx serving an HTML page **rendered from Helm values**, so every upgrade is visible.

```text
webapp/
├── Chart.yaml               # name, chart version 0.1.0, appVersion 1.27-alpine
├── values.yaml              # defaults: replicaCount 2, image nginx:1.27-alpine, page.{title,message,color,version}
├── charts/                  # sub-chart dependencies (none)
└── templates/
    ├── _helpers.tpl         # named templates: webapp.fullname, webapp.labels, ...
    ├── configmap.yaml       # ★ added: index.html built from .Values.page + .Release.Revision
    ├── deployment.yaml      # ★ edited: mounts the page ConfigMap; checksum/page annotation
    ├── service.yaml
    ├── serviceaccount.yaml
    ├── ingress.yaml / httproute.yaml / hpa.yaml   # off by default (enabled via values)
    ├── NOTES.txt            # printed after install/upgrade
    └── tests/test-connection.yaml   # `helm test`
```

Key template tricks:
```yaml
# configmap.yaml
<p>version: {{ .Values.page.version }} | release: {{ .Release.Name }} | revision: {{ .Release.Revision }}</p>
# deployment.yaml: roll Pods whenever the page content changes
checksum/page: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```

---

## Task 1: Helm commands

![helm commands](screenshots/commands.png)

| Command | What it does | What I saw |
|---|---|---|
| `helm create demo-chart` | scaffolds a chart (Chart.yaml, values.yaml, templates/, helpers, tests) | the standard file layout |
| `helm lint webapp` | checks the chart for errors and best practices | `1 chart(s) linted, 0 chart(s) failed` (info: icon recommended) |
| `helm template kirana webapp` | renders the manifests locally, without installing | ServiceAccount, ConfigMap, Service, Deployment, test Pod |
| **`helm install kirana ./webapp -n s15 --wait`** | installs the chart as release `kirana` and waits for readiness | `STATUS: deployed  REVISION: 1` + NOTES |
| **`helm list -n s15`** / `-A` | lists releases (all namespaces with `-A`) | `kirana  s15  1  deployed  webapp-0.1.0  1.27-alpine` |
| **`helm status kirana`** | release status, last deploy time, notes | `STATUS: deployed` |
| `helm get manifest kirana \| kubectl get -f -` | the release's live objects (Helm 4 removed `status --show-resources`) | Deployment 2/2, Service, ConfigMap, ServiceAccount |
| **`helm get values kirana`** (`--all`) | values supplied by the user (or all computed values) | `null` at first (defaults only) |
| `helm get manifest` / `notes` / `metadata` | the rendered YAML / NOTES / chart, version, status | — |
| **`helm upgrade kirana ./webapp --set replicaCount=3 --set page.version=v2 …`** | applies new values or chart version, giving a new revision | `REVISION: 2`, Deployment `3/3`, page shows `version: v2` |
| **`helm history kirana`** | all revisions with status and description | `1 superseded Install complete`, `2 deployed Upgrade complete` |
| **`helm rollback kirana 1`** | redeploys an old revision **as a new revision** | `Rollback was a success!`, revision 3 = "Rollback to 1", back to 2 replicas and the v1 page |
| **`helm repo add bitnami …`**, `add ingress-nginx …`, `update`, `list` | manage chart repositories | both added and indexed |
| **`helm search repo nginx`** | search added repos | `bitnami/nginx 25.2.1`, `ingress-nginx/ingress-nginx 4.15.1`, … |
| `helm search repo … --versions` | all versions of a chart | 4.15.1, 4.15.0, 4.14.5 … |
| **`helm search hub prometheus`** | search Artifact Hub (public catalogue) | prometheus-community/prometheus 29.35.0 … |
| `helm show chart` / `show values bitnami/nginx` | inspect a chart before installing | `appVersion: 1.31.6`, default `replicaCount: 1` |
| **`helm uninstall kirana --wait`** | deletes every resource of the release and its history | `release "kirana" uninstalled`, `kubectl get all` → none |

Install output:
```text
$ helm install kirana ./webapp -n s15 --wait --timeout 3m
NAME: kirana
NAMESPACE: s15
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
```

## Task 2: Helm rollback

Workflow: **Install → Upgrade → Verify → Upgrade again → Verify → Rollback → Verify**. The second upgrade is a
deliberately **bad release** (an image tag that doesn't exist), the realistic reason you'd roll back.

![helm rollback](screenshots/rollback.png)

| Step | Command | Result |
|---|---|---|
| 1. **Install** | `helm install kirana ./webapp -n s15 --wait` | revision 1: 2 Pods, green page *"Namaste! Release v1 deployed with Helm."* |
| 2. Verify | `helm history`, `kubectl get deploy`, curl | `1 deployed`, `nginx:1.27-alpine`, page `version: v1 \| revision: 1` |
| 3. **Upgrade** | `helm upgrade … --reuse-values --set replicaCount=3 --set page.version=v2 --set page.color='#1565c0' --set page.message='Release v2: new blue theme' --wait` | revision 2 |
| 4. Verify | same | `2 deployed`, `3/3` ready, page *"Release v2: new blue theme"* |
| 5. **Upgrade again** | `helm upgrade … --reuse-values --set image.tag=9.99-does-not-exist --set page.version=v3 --wait --timeout 60s` | **`Error: UPGRADE FAILED: resource Deployment/s15/kirana-webapp not ready … Updated: 1/3`** |
| 6. Verify | `helm history`, `kubectl get pods` | `3 failed`; the new Pod is in `ErrImagePull`, while the **3 old v2 Pods keep `Running` and keep serving** (RollingUpdate protects availability) |
| 7. **Rollback** | `helm rollback kirana 2 -n s15 --wait` | `Rollback was a success! Happy Helming!` |
| 8. Verify | `helm history`, pods, `helm get values`, curl | `4 deployed "Rollback to 2"`, 3 Pods Running on `nginx:1.27-alpine`, values back to v2, page *"Release v2: new blue theme \| version: v2"* |

Final history:
```text
REVISION  STATUS      DESCRIPTION
1         superseded  Install complete
2         superseded  Upgrade complete
3         failed      Upgrade "kirana" failed: resource Deployment/s15/kirana-webapp not ready ...
4         deployed    Rollback to 2
```

**What I learned**
- **Rollback never rewrites history.** It creates a new revision (4) that's a copy of the target (2). You can even roll back a rollback.
- `--wait` (with `--timeout`) makes Helm **fail the release** when resources don't become ready. Without it, the bad upgrade would have been marked `deployed`.
  In Helm 4, `--rollback-on-failure` (formerly `--atomic`) would have rolled back automatically.
- `--reuse-values` keeps earlier `--set` values on upgrade. Without it, an upgrade starts again from the chart defaults.
- **ConfigMap-volume caveat:** after the rollback, the ConfigMap went back to revision 2 at once. But the running Pods weren't restarted (their template already matched revision 2),
  so their mounted `index.html` followed only after the kubelet's next volume sync. In one run it still served the v3 page for a few seconds. The demo waits for the sync.
  The `checksum/page` annotation makes sure any **forward** change of page content does restart the Pods.

## Task 3: Mini project

> ⏳ **Pending:** the Helm mini project from the course material hasn't been provided to me yet. It will be added here once available.
