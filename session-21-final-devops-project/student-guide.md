# Session 21 — Student Guide: Submission Instructions

How to submit the Kirana Ledger capstone: what to hand in, the rules, the one step still left, and the
order of the final demo. The rubric is in [GRADING.md](GRADING.md); the project is described in
[README.md](README.md); the slides are in [presentation/](presentation/index.html).

---

## 1. What to submit

Submit one link, **<https://github.com/milap1afk/devops-homework/tree/main/session-21-final-devops-project>**.
Everything below is already in the repo.

| # | Item | Where |
|---|---|---|
| 1 | Source: backend, frontend, Alembic, tests | `final-devops-project/application/` |
| 2 | `docker-compose.yml` and both Dockerfiles | `final-devops-project/docker/`, `application/*/Dockerfile` |
| 3 | Workflow file | `../.github/workflows/s21-final.yml` |
| 4 | Terraform code + `terraform.tfvars.example` | `final-devops-project/terraform/` |
| 5 | Namespace, Helm chart, monitoring values, Argo CD app | `final-devops-project/k8s/`, `helm/kirana/`, `monitoring/`, `gitops/` |
| 6 | Screenshots (29) | `screenshots/` |
| 7 | Captured terminal output | `output-*.txt` |
| 8 | GitHub Actions run URL | [GRADING.md, M5](GRADING.md#m5--cicd-15) |
| 9 | Trivy explanation | [GRADING.md, M6](GRADING.md#m6--devsecops-5) |
| 10 | Presentation | `presentation/index.html` (open in a browser; ← → to move, F for full screen) and `presentation/Kirana-Ledger-Session21.pdf` |
| 11 | Live demo | presentation session (section 4); recorded evidence in [README §8](README.md#8-live-demo-recorded-commit--pipeline--deployment-updates) |

## 2. Rules before you submit

1. **No secrets in Git, ever.** No AWS keys, no real `terraform.tfvars`, no `.env`, no API keys or DB passwords.
   Secrets go in with `kubectl create secret` / `--set` at install time, and in CI as GitHub Actions secrets
   (`KIRANA_API_KEY`). The Gitleaks job scans the whole history.
2. **Images are tagged with the commit SHA**, never `latest`.
3. **The pipeline must be green** on the commit you submit. Check the
   [Actions tab](https://github.com/milap1afk/devops-homework/actions/workflows/s21-final.yml).
4. **Commits are yours:** author `Milap Kothari <milapkothari27@gmail.com>`, meaningful messages
   ("Session 21: …", saying what changed and why). In a fresh clone, set
   `git config user.email milapkothari27@gmail.com` first: this Mac's global git email belongs to another account.
5. **Destroy AWS resources** the same day you create them (`terraform destroy`) and keep the screenshot.
6. **Own domain.** The application must be your own; only the DevOps architecture may follow TaskBoard.
7. **Deadline.** 5 points are lost per 24 hours late.

## 3. What is still left: the AWS run

Every module has its evidence except the real AWS part of **M7 (9 points)**. You need an AWS account with
billing and the AWS CLI (`brew install awscli`). EKS takes about 15 minutes to create. Expect a few US dollars
if you destroy within a couple of hours: the EKS control plane, a NAT gateway and 2 × `t3.medium` are billed
per hour.

```bash
cd session-21-final-devops-project/final-devops-project/terraform
cp terraform.tfvars.example terraform.tfvars      # gitignored; delete the "offline_plan = true" line
aws configure                                     # credentials stay in ~/.aws, never in the repo
terraform init && terraform plan                  # → screenshots/aws-terraform-plan.png
terraform apply                                   # ~15 min
$(terraform output -raw kubeconfig_command)
kubectl get nodes                                 # → screenshots/aws-eks-nodes.png
```

AWS Console, region **ap-south-1**: VPC `kirana-eks-vpc` with its 4 subnets → `screenshots/aws-vpc.png`; EKS
cluster `kirana-eks` with the node group `Active` → `screenshots/aws-eks.png`. Then, in the same session:

```bash
terraform destroy                                 # → screenshots/aws-terraform-destroy.png ("Destroy complete!")
```

Optional, while the cluster exists: deploy the same chart to EKS with
`scripts/deploy-minikube.sh <sha>` (the images are multi-arch and public, so EKS can pull them).

Afterwards, tick the M7 rows in [GRADING.md](GRADING.md), add the screenshots to README §5, commit and push.

## 4. Final demo script

About 12 minutes. Before you start, run these and open the tabs:

```bash
minikube start                                    # cluster with Argo CD, ingress-nginx, monitoring already installed
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8089:80 &
kubectl -n monitoring port-forward svc/monitoring-grafana 3001:80 &
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 &
# /etc/hosts:  127.0.0.1 kirana.local     → app at http://kirana.local:8089
```

Tabs: the app, the [Actions tab](https://github.com/milap1afk/devops-homework/actions/workflows/s21-final.yml),
GHCR, Prometheus Targets, the Grafana "Kirana Ledger" dashboard, and the slides.

| # | Show | Command / page | Say |
|---|---|---|---|
| 1 | Slides 1–5 | `presentation/index.html` | problem, app, architecture |
| 2 | Application | `kirana.local:8089`: **New entry** "Ramesh bhai ₹500 udhar" → "sahi hai?" → save; then a ₹200 payment | names are stored without honorifics; KPIs and chart update; WhatsApp reminder |
| 3 | API | backend `/docs` (`kubectl -n kirana port-forward svc/kirana-backend 8000:80`) | 12 endpoints; writes need `X-API-Key` |
| 4 | Database | `kubectl -n kirana exec -it kirana-postgres-0 -- psql -U kirana -d ledger -c 'select * from entries order by id desc limit 5;'` | Alembic created this table |
| 5 | Git | change `config.SHOP_NAME` in `values-minikube.yaml`, or a UI label; `git commit -m "Session 21: …"`; `git push` | small, reviewable change |
| 6 | CI | Actions tab: job 1 running pytest | tests gate everything after them |
| 7 | Docker | job 6: four builds on amd64 + arm64 runners | multi-stage frontend, non-root images |
| 8 | Security | jobs 2–5, 7 and the gate (job 8) | Trivy: 0 fixable HIGH/CRITICAL; the gate blocks the push if any scan fails |
| 9 | Registry | GHCR package page | the tag equals the commit SHA just pushed; OS/Arch = 2 |
| 10 | Terraform | slide 11, `terraform/network.tf`, `eks.tf` | IaC instead of clicking in the console |
| 11 | Kubernetes | `kubectl -n kirana get pods,svc,ingress` | 2+ Pods per tier, Postgres StatefulSet with a PVC |
| 12 | Helm | job 10 log (`helm list`), `helm/kirana/` | chart, values, templates; upgrade and rollback |
| 13 | Ingress | `kirana.local:8089` | `/api` → backend, `/` → frontend; Ingress needs a controller |
| 14 | HPA | `kubectl -n kirana get hpa -w` while running the load loop from README §6 | CPU above 60 % → 3 Pods |
| 15 | Monitoring | Prometheus Targets, Grafana "Kirana Ledger" | requests/s, p95 latency, entries by type |
| 16 | Deployment updated | step 5's commit: `kubectl -n argocd get application kirana-final` → Synced/Healthy; status pill shows the new SHA | Argo CD rolled it out from Git |
| 17 | Failure | slide 16, or `bash troubleshooting/resilience-check.sh` | readiness vs liveness; describe → events → logs |

Steps 5, 6 and 16 together are the M10 live-demo points: commit → pipeline → updated deployment. For a UI
change to reach minikube, set the new SHA in `values-minikube.yaml` once the pipeline is green (the
"promote" step in README §8). A `SHOP_NAME` change syncs immediately.

**Tip for an 8 GB laptop:** close other apps and stop Docker Compose before the demo. Under heavy load, the
minikube node ran out of memory and Prometheus restarted (README §7).

### Questions to be ready for

- Why are `/health` and `/ready` separate? (Liveness must not depend on the DB, or a DB blip restarts every API Pod.)
- Why are migrations an initContainer and not part of app start-up?
- Why tag images with the SHA instead of `latest`?
- Why build amd64 *and* arm64? (Incident 2: `exec format error` on Apple Silicon.)
- What does the security gate do when one scan fails?
- Postgres in Kubernetes vs Amazon RDS: what would you use in production, and why?
- Why does an Ingress resource do nothing without an Ingress controller?
- What did the Postgres CrashLoopBackOff incident teach you about liveness probes?
