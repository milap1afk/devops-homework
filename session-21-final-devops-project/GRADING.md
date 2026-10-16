# Session 21 — Grading Rubric and Self-Assessment

The capstone is graded out of **100 points** using the course rubric
([original GRADING.md](https://github.com/Nency-Ravaliya/devops-heros/blob/main/session21-python/GRADING.md)).
A skipped module scores zero; partial credit is given only inside a module.

This file repeats every criterion and marks where Kirana Ledger stands, with links to the evidence.
Screenshots are in [`screenshots/`](screenshots); paths below are relative to this folder.

**Status key:** ✅ done, with evidence in the repo · ⚠️ partly done · ❌ not done yet

## Summary

| Module | Topic | Points | Status | Evidenced |
|---|---|---:|---|---:|
| M1 | Application: frontend + backend + database | 10 | ✅ | 10 |
| M2 | Testing: pytest + code quality | 10 | ✅ | 10 |
| M3 | Git and GitHub | 5 | ✅ | 5 |
| M4 | Docker: Dockerfiles + Compose | 10 | ✅ | 10 |
| M5 | CI/CD: GitHub Actions | 15 | ✅ | 15 |
| M6 | DevSecOps: Trivy | 5 | ✅ | 5 |
| M7 | Terraform: AWS IaC | 15 | ⚠️ code + plan only, no real AWS apply | 6 |
| M8 | Kubernetes + Helm | 15 | ✅ | 15 |
| M9 | Observability: Prometheus + Grafana | 10 | ✅ | 10 |
| M10 | Presentation + documentation | 5 | ✅ deck + recorded demo; present it live | 5 |
| **Total** | | **100** | | **91** |

**The only gap is M7 (9 points):** the rubric wants a VPC and EKS really created on AWS (Console screenshot)
and then destroyed. That needs an AWS account with billing, which this project has not used yet.
[student-guide.md §3](student-guide.md#3-what-is-still-left-the-aws-run) has the exact steps; it takes about
30 minutes and costs a few US dollars if you destroy the same day.

---

## M1 — Application (10)

| Criterion | Pts | Status | Evidence |
|---|---:|---|---|
| FastAPI backend starts and answers `/health` | 2 | ✅ | Compose healthcheck + K8s liveness probe; [output-compose.txt](output-compose.txt) |
| ≥ 4 REST endpoints (GET, POST, PUT, DELETE) | 3 | ✅ | 12 endpoints in [`app/main.py`](final-devops-project/application/backend/app/main.py); CRUD calls in [output-compose.txt](output-compose.txt) |
| PostgreSQL table managed by Alembic | 2 | ✅ | [`0001_create_entries.py`](final-devops-project/application/backend/alembic/versions/0001_create_entries.py); Compose `migrate` exits 0; K8s initContainer |
| Frontend renders and calls the API | 2 | ✅ | [`src/main.js`](final-devops-project/application/frontend/src/main.js) calls `/api/stats`, `/api/entries`, `/api/customers`, `/api/info` |
| Responsive, usable UI | 1 | ✅ | [desktop](screenshots/app-dashboard-light.png), [phone](screenshots/app-mobile-dashboard.png), [dark](screenshots/app-dashboard-dark.png), [ledger](screenshots/app-ledger.png), [customers](screenshots/app-customers.png), [entry dialog](screenshots/app-new-entry.png) |

## M2 — Testing (10)

| Criterion | Pts | Status | Evidence |
|---|---:|---|---|
| `pytest` runs without errors | 3 | ✅ | **21 passed**: [output-pytest.txt](output-pytest.txt), [screenshot](screenshots/pytest.png); also job 1 of every CI run |
| ≥ 5 tests covering ≥ 3 endpoints | 4 | ✅ | 21 tests cover `/health`, `/ready`, `/metrics`, `/api/stats`, all `/api/entries` routes and filters, `/api/customers` |
| Test DB or mock, not production | 2 | ✅ | [`tests/conftest.py`](final-devops-project/application/backend/tests/conftest.py): new SQLite file per test via `dependency_overrides` |
| `pytest.ini` / `conftest.py` configured | 1 | ✅ | [`pytest.ini`](final-devops-project/application/backend/pytest.ini) + `conftest.py` |

Extra: `flake8` is clean and CI fails under 80 % coverage (current: 91.6 %).

## M3 — Git and GitHub (5)

| Criterion | Pts | Status | Evidence |
|---|---:|---|---|
| Public repository | 2 | ✅ | <https://github.com/milap1afk/devops-homework> (public) |
| Meaningful commit messages | 2 | ✅ | 28 commits, e.g. "Session 21: build multi-arch images (amd64 + arm64) - fixes exec format error on minikube" |
| `.gitignore` excludes `.env`, `__pycache__`, `node_modules`, `.venv` | 1 | ✅ | [`../.gitignore`](../.gitignore) |

## M4 — Docker (10)

| Criterion | Pts | Status | Evidence |
|---|---:|---|---|
| `backend/Dockerfile` builds | 2 | ✅ | [`backend/Dockerfile`](final-devops-project/application/backend/Dockerfile); built by Compose and by CI on amd64 and arm64 |
| Frontend multi-stage (Node build → Nginx) | 3 | ✅ | [`frontend/Dockerfile`](final-devops-project/application/frontend/Dockerfile): `node:22-alpine` → `nginx-unprivileged` |
| Images run as non-root | 2 | ✅ | backend `USER 10001`, frontend `USER 101` |
| `docker compose up --build` starts frontend, backend, postgres | 3 | ✅ | [compose-up-build.txt](compose-up-build.txt), [screenshot](screenshots/compose.png); app at `localhost:3000` |

## M5 — CI/CD (15)

| Criterion | Pts | Status | Evidence |
|---|---:|---|---|
| Workflow file in `.github/workflows/` | 1 | ✅ | [`../.github/workflows/s21-final.yml`](../.github/workflows/s21-final.yml) |
| Triggers on push to `main` | 1 | ✅ | `on: push: branches: [main]` |
| pytest job fails the build on failure | 3 | ✅ | job 1; every later job `needs` it |
| Frontend built in the pipeline | 2 | ✅ | job 1: `npm ci && npm run build` |
| Images built for both tiers | 3 | ✅ | job 6: 2 tiers × amd64/arm64 on native runners |
| Images pushed to GHCR | 3 | ✅ | job 9; [GHCR screenshot](screenshots/ghcr.png) |
| Tags use the commit SHA, not `latest` | 2 | ✅ | `TAG: ${{ github.sha }}`; GHCR shows `41ee491…` tags |

Green run (17/17 jobs): <https://github.com/milap1afk/devops-homework/actions/runs/38857331818>,
[screenshot](screenshots/pipeline.png).

## M6 — DevSecOps (5)

| Criterion | Pts | Status | Evidence |
|---|---:|---|---|
| Trivy scans both images in CI | 3 | ✅ | job 7 (4 images); also Trivy fs (job 3) and Trivy config (job 5) |
| Fails on HIGH/CRITICAL | 1 | ✅ | [`security/trivy.yaml`](final-devops-project/security/trivy.yaml): `severity: [CRITICAL, HIGH]`, `exit-code: 1`, `ignore-unfixed: true` |
| Can explain a CVE or a clean result | 1 | ✅ | below, plus [output-trivy.txt](output-trivy.txt) and the [screenshot](screenshots/trivy.png) |

**What Trivy scanned and what the result means.** Trivy unpacked all four images (2 tiers × 2 architectures)
and checked every OS package (Debian 13.7 in the backend, Alpine 3.23.4 in the frontend) and all 31 Python
packages against its vulnerability database. It found **0 HIGH/CRITICAL vulnerabilities that have a fix**, so the
gate passed. That is partly by design: both Dockerfiles upgrade OS packages at build time. "Clean" only means no
known, fixable issue today. Unfixed CVEs are ignored on purpose, and a new CVE can appear tomorrow, which is why
the scan runs on every push.

## M7 — Terraform (15)

| Criterion | Pts | Status | Evidence |
|---|---:|---|---|
| `terraform/` with valid HCL | 2 | ✅ | `terraform validate` → "Success!" in [`terraform/output.txt`](final-devops-project/terraform/output.txt); also CI job 5 |
| `terraform init` succeeds | 1 | ✅ | same file |
| `terraform plan` non-empty, no errors | 2 | ✅ | **Plan: 26 to add** ([screenshot](screenshots/terraform-plan.png); offline plan, dummy credentials) |
| VPC with ≥ 2 public subnets **provisioned** | 3 | ❌ | coded in [`network.tf`](final-devops-project/terraform/network.tf) (2 public + 2 private); not applied to AWS |
| EKS with ≥ 1 node group **provisioned** | 4 | ❌ | coded in [`eks.tf`](final-devops-project/terraform/eks.tf) (`t3.medium`, 2–4 nodes); not applied |
| `terraform destroy` cleans up | 2 | ❌ | needs a real apply first |
| `terraform.tfvars.example`, no credentials committed | 1 | ✅ | [`terraform.tfvars.example`](final-devops-project/terraform/terraform.tfvars.example); Gitleaks job passes |

## M8 — Kubernetes + Helm (15)

| Criterion | Pts | Status | Evidence |
|---|---:|---|---|
| `k8s/namespace.yaml` applies | 1 | ✅ | [`k8s/namespace.yaml`](final-devops-project/k8s/namespace.yaml); applied by CI job 10 |
| Chart with `Chart.yaml`, `values.yaml`, templates | 3 | ✅ | [`helm/kirana`](final-devops-project/helm/kirana) (chart 2.1.0); `helm lint` in CI |
| `helm upgrade --install` succeeds | 3 | ✅ | CI job 10 with `--wait`: `helm list` shows `kirana-2.1.0 deployed`: [output-ci-helm.txt](output-ci-helm.txt), [screenshot](screenshots/ci-helm.png) |
| Backend and frontend ≥ 2 replicas each | 2 | ✅ | HPA `minReplicas: 2`; minikube shows 3 backend + 2 frontend: [screenshot](screenshots/k8s-cluster.png) |
| ClusterIP Services for both | 2 | ✅ | `kubectl get svc` in [output-cluster-after.txt](output-cluster-after.txt) |
| Ingress: `/` → frontend, `/api` → backend | 2 | ✅ | [`ingress.yaml`](final-devops-project/helm/kirana/templates/ingress.yaml); app opened at `kirana.local`: [screenshot](screenshots/k8s-ingress-after.png) |
| All Pods `Running` | 2 | ✅ | [screenshot](screenshots/k8s-cluster.png), CI log |

On minikube the chart is applied by Argo CD (GitOps), so `helm list` there is empty by design. The `helm list`
evidence comes from the pipeline's `helm upgrade --install`, and
[`scripts/deploy-minikube.sh`](final-devops-project/scripts/deploy-minikube.sh) does the same on any cluster.
Bonus: HPA scaling 2 → 3 under load ([screenshot](screenshots/hpa-scale.png)).

## M9 — Observability (10)

| Criterion | Pts | Status | Evidence |
|---|---:|---|---|
| `/metrics` returns Prometheus format | 2 | ✅ | [output-metrics.txt](output-metrics.txt) (`http_requests_total`, `kirana_ledger_entries_total`), [screenshot](screenshots/metrics.png) |
| Prometheus installed and scraping the app | 3 | ✅ | Targets page: `serviceMonitor/kirana/kirana-backend` **3/3 UP**: [screenshot](screenshots/prometheus-targets.png); alert rules: [screenshot](screenshots/prometheus-alerts.png) |
| Grafana installed and reachable | 2 | ✅ | kube-prometheus-stack 92.0.0 in namespace `monitoring` |
| Grafana panel with live app metrics | 3 | ✅ | "Kirana Ledger" dashboard: requests/s, p95 latency, ledger entries, ready Pods, CPU: [screenshot](screenshots/grafana-kirana.png) |

## M10 — Presentation + documentation (5)

| Criterion | Pts | Status | Evidence |
|---|---:|---|---|
| `README.md` explains the application | 2 | ✅ | [README.md](README.md) |
| Live demo: commit → pipeline → deployment updates | 3 | ✅ | Done for real and recorded: [README §8](README.md#8-live-demo-recorded-commit--pipeline--deployment-updates), [output-gitops-rollout.txt](output-gitops-rollout.txt); slides: [presentation/](presentation/index.html) ([PDF](presentation/Kirana-Ledger-Session21.pdf)) |

The live demo still has to be shown in the presentation session: script in [student-guide.md §4](student-guide.md#4-final-demo-script).

---

## Submission checklist (from the rubric)

```text
Application
  [x] GitHub repository URL submitted          https://github.com/milap1afk/devops-homework
  [x] Application runs via docker compose up --build
  [x] At least 4 REST API endpoints implemented (12)
  [x] Alembic migration file present

Testing
  [x] pytest passes (screenshot submitted)     screenshots/pytest.png
  [x] At least 5 test cases present            21

Docker
  [x] backend/Dockerfile builds
  [x] frontend/Dockerfile uses multi-stage build
  [x] Non-root user in both Dockerfiles

CI/CD
  [x] GitHub Actions workflow present
  [x] Pipeline runs on push to main
  [x] pytest runs in pipeline
  [x] Images pushed to GHCR with SHA tags      screenshots/ghcr.png

Security
  [x] Trivy scan in pipeline                   screenshots/trivy.png
  [x] No secrets committed to Git              Gitleaks job passes

Terraform
  [x] terraform plan output submitted          screenshots/terraform-plan.png (offline plan)
  [ ] VPC + EKS provisioned (AWS Console screenshot)
  [ ] terraform destroy output submitted

Kubernetes + Helm
  [x] kubectl get pods screenshot (all Running)  screenshots/k8s-cluster.png
  [x] helm list screenshot                       screenshots/ci-helm.png
  [x] Application accessible via Ingress         screenshots/k8s-ingress-after.png

Observability
  [x] /metrics endpoint screenshot             screenshots/metrics.png
  [x] Prometheus Targets page screenshot (UP)  screenshots/prometheus-targets.png
  [x] Grafana dashboard screenshot             screenshots/grafana-kirana.png

Documentation
  [x] README.md present
  [x] Presentation prepared                    presentation/ (HTML + PDF)
  [ ] Presentation delivered live (or recording submitted)
```

## Grading policy (from the course)

- Late submissions lose 5 points per 24 hours after the deadline.
- Copying another student, or cloning TaskBoard without meaningful changes, scores zero. Kirana Ledger is its own
  domain (credit ledger, honorific-free customer names, Hindi reminders), with its own API and frontend; only
  the DevOps architecture follows TaskBoard, which the rules allow.
- AWS costs are the student's responsibility: run `terraform destroy` after evaluation.
