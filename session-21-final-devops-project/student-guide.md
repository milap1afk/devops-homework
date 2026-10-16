# Session 21 — Student Guide: Submission Instructions

How to submit the Kirana Ledger capstone: what to hand in, how to capture each piece of evidence, the rules to
follow, and the order of the final demo. The rubric itself is in [GRADING.md](GRADING.md); the project is
described in [README.md](README.md).

---

## 1. What to submit

Submit one link, **<https://github.com/milap1afk/devops-homework/tree/main/session-21-final-devops-project>**, plus
the items below. Everything lives in the repo, so the grader needs nothing else.

| # | Item | Where it goes |
|---|---|---|
| 1 | Source: backend, frontend, Alembic, tests | `final-devops-project/application/` |
| 2 | `docker-compose.yml` and both Dockerfiles | `final-devops-project/docker/`, `application/*/Dockerfile` |
| 3 | Workflow file | `../.github/workflows/s21-final.yml` |
| 4 | Terraform code + `terraform.tfvars.example` | `final-devops-project/terraform/` |
| 5 | Namespace, Helm chart, monitoring values | `final-devops-project/k8s/`, `helm/kirana/`, `monitoring/` |
| 6 | Screenshots | `session-21-final-devops-project/screenshots/` (names in section 3) |
| 7 | Captured terminal output | `session-21-final-devops-project/output-*.txt` |
| 8 | GitHub Actions run URL | [GRADING.md, M5](GRADING.md#m5--cicd-15) |
| 9 | Trivy explanation (2–3 sentences) | [GRADING.md, M6](GRADING.md#m6--devsecops-5) |
| 10 | Live demo, or a recorded walkthrough if remote | presentation session |

## 2. Rules before you submit

1. **No secrets in Git, ever.** No AWS keys, no real `terraform.tfvars`, no `.env`, no API keys or DB passwords.
   Secrets go in with `--set` or `kubectl create secret` at install time, and in CI as GitHub Actions secrets
   (`KIRANA_API_KEY`). The Gitleaks job scans the whole history; a leaked key means a rejected submission even if
   it is deleted later. If one slips in: revoke it first, then clean the history.
2. **Images are tagged with the commit SHA**, never `latest`.
3. **The pipeline must be green** on the commit you submit. Check the
   [Actions tab](https://github.com/milap1afk/devops-homework/actions/workflows/s21-final.yml).
4. **Meaningful commit messages** ("Session 21: ...", saying what changed and why), not "update" or "fix".
5. **Destroy AWS resources** the same day you create them (`terraform destroy`) and keep the screenshot.
6. **Own domain.** The application must be your own; only the DevOps architecture may follow TaskBoard.
7. **Deadline.** 5 points are lost per 24 hours late.

## 3. What is still left to capture

Code for every module is finished. These items are the 20 points that still need evidence (see the
[GRADING.md summary](GRADING.md#summary)). Save each screenshot under `screenshots/` with the file name shown.

### M2 / M5 / M9 — quick screenshots (no cluster needed)

```bash
cd session-21-final-devops-project/final-devops-project/application/backend
pytest -v                                             # → screenshots/pytest.png
cd ../.. && docker compose -f docker/docker-compose.yml up --build -d
curl -s localhost:8001/metrics | head -30             # → screenshots/metrics.png
```

GHCR: open <https://github.com/milap1afk?tab=packages>, then `kirana-backend` → screenshot showing the SHA tags
(`screenshots/ghcr.png`).

### M8 — Kubernetes + Helm on minikube (2 points)

```bash
minikube start --memory 3500 --cpus 4
minikube addons enable ingress && minikube addons enable metrics-server
cd session-21-final-devops-project/final-devops-project
docker build -t ghcr.io/milap1afk/kirana-backend:2.0.0  application/backend
docker build -t ghcr.io/milap1afk/kirana-frontend:2.0.0 application/frontend
minikube image load ghcr.io/milap1afk/kirana-backend:2.0.0 ghcr.io/milap1afk/kirana-frontend:2.0.0
kubectl apply -f k8s/namespace.yaml
kubectl -n kirana create secret generic kirana-secrets \
  --from-literal=API_KEY="$(openssl rand -hex 16)" --from-literal=POSTGRES_PASSWORD="$(openssl rand -hex 16)"
helm upgrade --install kirana helm/kirana -n kirana -f helm/kirana/values-minikube.yaml \
  --set monitoring.serviceMonitor=false --set monitoring.prometheusRule=false --set monitoring.grafanaDashboard=false \
  --wait --timeout 6m

kubectl get pods -n kirana        # → screenshots/k8s-pods.png
kubectl get svc,ingress,hpa -n kirana   # → screenshots/k8s-svc.png
helm list -n kirana               # → screenshots/helm-list.png
```

Ingress in the browser: run `minikube tunnel` in a second terminal, add `127.0.0.1 kirana.local` to
`/etc/hosts`, open <http://kirana.local> → `screenshots/app-ingress.png`.
(With the Docker driver on macOS the tunnel exposes the Ingress on 127.0.0.1.)

### M9 — Prometheus + Grafana (6 points)

Install the stack first (the chart's ServiceMonitor needs its CRDs), then turn monitoring on in the release:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --version 92.0.0 \
  -n monitoring --create-namespace -f monitoring/kube-prometheus-stack-values.yaml --wait
helm upgrade kirana helm/kirana -n kirana -f helm/kirana/values-minikube.yaml   # monitoring.* default to true

kubectl -n kirana port-forward svc/kirana-frontend 8080:80 &      # create some traffic in the UI
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 &
kubectl -n monitoring port-forward svc/monitoring-grafana 3001:80 &
```

- <http://localhost:9090/targets>, Kirana backend target `UP` → `screenshots/prometheus-targets.png`
- <http://localhost:3001>, dashboard "Kirana Ledger" with data → `screenshots/grafana-kirana.png`

On 8 GB RAM, stop Compose and other clusters first; [README §8](README.md#8-troubleshooting-a-real-incident)
shows what happens when the node runs out of CPU.

### M7 — Terraform on real AWS (9 points)

Needs an AWS account with billing set up. Expect a few US dollars if you destroy within a couple of hours.

```bash
cd session-21-final-devops-project/final-devops-project/terraform
cp terraform.tfvars.example terraform.tfvars      # gitignored; delete the "offline_plan = true" line
aws configure                                     # credentials stay in ~/.aws, never in the repo
terraform init && terraform plan                  # → screenshots/terraform-plan.png
terraform apply                                   # ~15 min for EKS
```

AWS Console, region **ap-south-1**: VPC `kirana-*` with its subnets, and EKS cluster `kirana-eks` with the node
group `Active` → `screenshots/aws-vpc.png`, `screenshots/aws-eks.png`. Then, the same session:

```bash
terraform destroy                                 # → screenshots/terraform-destroy.png ("Destroy complete!")
```

### After capturing

Add the new screenshots to [README.md](README.md) and tick the boxes in [GRADING.md](GRADING.md), then commit
and push.

## 4. Final demo script

About 10 minutes, in the order the brief asks. Have Compose (or minikube) running and the Actions tab open first.

| # | Show | Command / page | Say |
|---|---|---|---|
| 1 | Application | <http://localhost:3000>: add "Ramesh bhai ₹500 udhar", then a ₹200 payment | names are stored without honorifics; balance and WhatsApp reminder |
| 2 | API | <http://localhost:8001/docs>: run GET/POST/PUT/DELETE | 11 endpoints; writes need `X-API-Key` |
| 3 | Database | `docker compose -f docker/docker-compose.yml exec postgres psql -U kirana -d ledger -c 'select * from entries;'` | Alembic created this table |
| 4 | Git | change `SHOP_NAME`/a label, `git commit -m "Session 21: ..."`, `git push` | small, reviewable change |
| 5 | CI | Actions tab: job 1 running pytest | tests gate everything after them |
| 6 | Docker | job 6, plus `docker images \| grep kirana` | multi-stage frontend, non-root images |
| 7 | Security | jobs 2–5, 7 and the gate (job 8) | Trivy: 0 fixable HIGH/CRITICAL; the gate blocks the push if any scan fails |
| 8 | Registry | GHCR package page | the tag equals the commit SHA just pushed |
| 9 | Terraform | `terraform/network.tf`, `eks.tf`, the plan / Console screenshots | IaC instead of clicking in the console |
| 10 | Kubernetes | `kubectl get pods,svc -n kirana` | 2 + 2 Pods, Postgres StatefulSet with a PVC |
| 11 | Helm | `helm list -n kirana`, `helm history kirana -n kirana` | upgrade and rollback |
| 12 | Ingress | <http://kirana.local> | `/api` → backend, `/` → frontend; Ingress needs a controller |
| 13 | HPA | `kubectl get hpa -n kirana` | CPU target 60 %, needs metrics-server and resource requests |
| 14 | Monitoring | Prometheus Targets, Grafana "Kirana Ledger" | requests/s, p95 latency, 5xx share |
| 15 | Failure | `bash troubleshooting/resilience-check.sh` or apply a wrong image tag | readiness vs liveness; describe → events → logs |
| 16 | Deployment updated | job 10 log, or `helm upgrade` with the new SHA | the change from step 4 is now running |

Steps 4, 5 and 16 together are the M10 live-demo points: commit → pipeline → updated deployment.

### Questions to be ready for

- Why are `/health` and `/ready` separate? (Liveness must not depend on the DB, or a DB blip restarts every API Pod.)
- Why are migrations an initContainer and not part of app start-up?
- Why tag images with the SHA instead of `latest`?
- What does the security gate do when one scan fails?
- Postgres in Kubernetes vs Amazon RDS: what would you use in production, and why?
- Why does an Ingress resource do nothing without an Ingress controller?
- What did the Postgres CrashLoopBackOff incident teach you about liveness probes?
