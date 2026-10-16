# Session 21 — Grading Rubric and Self-Assessment

The capstone is graded out of **100 points** using the course rubric
([original GRADING.md](https://github.com/Nency-Ravaliya/devops-heros/blob/main/session21-python/GRADING.md)).
A skipped module scores zero; partial credit is given only inside a module.

This file repeats every criterion and marks where Kirana Ledger stands, with links to the evidence.
Paths below are relative to [`final-devops-project/`](final-devops-project) unless they start with `../`.

**Status key:** ✅ done, with evidence in the repo · ⚠️ built, but the evidence the rubric asks for is still missing · ❌ not done yet

## Summary

| Module | Topic | Points | Status | Verified now |
|---|---|---:|---|---:|
| M1 | Application: frontend + backend + database | 10 | ✅ | 10 |
| M2 | Testing: pytest + code quality | 10 | ✅ | 10 |
| M3 | Git and GitHub | 5 | ✅ | 5 |
| M4 | Docker: Dockerfiles + Compose | 10 | ✅ | 10 |
| M5 | CI/CD: GitHub Actions | 15 | ✅ | 15 |
| M6 | DevSecOps: Trivy | 5 | ✅ | 5 |
| M7 | Terraform: AWS IaC | 15 | ⚠️ no real `apply` yet | 6 |
| M8 | Kubernetes + Helm | 15 | ⚠️ screenshots missing | 13 |
| M9 | Observability: Prometheus + Grafana | 10 | ⚠️ Kirana screenshots missing | 4 |
| M10 | Presentation + documentation | 5 | ⚠️ live demo pending | 2 |
| **Total** | | **100** | | **80** |

**80 / 100 can be shown today. The other 20 points need evidence, not new code:** a real AWS apply/destroy (M7),
cluster screenshots (M8, M9) and the live demo (M10). [student-guide.md](student-guide.md#3-what-is-still-left-to-capture)
lists the exact commands.

---

## M1 — Application (10)

| Criterion | Pts | Status | Evidence |
|---|---:|---|---|
| FastAPI backend starts and answers `/health` | 2 | ✅ | `curl localhost:8001/health` → `{"status":"ok",...}` (re-checked 2026-10-16) |
| ≥ 4 REST endpoints (GET, POST, PUT, DELETE) | 3 | ✅ | 11 endpoints in [`app/main.py`](final-devops-project/application/backend/app/main.py); every CRUD call in [`../output-compose.txt`](output-compose.txt) |
| PostgreSQL table managed by Alembic | 2 | ✅ | [`alembic/versions/0001_create_entries.py`](final-devops-project/application/backend/alembic/versions/0001_create_entries.py); Compose `migrate` service exits 0 |
| Frontend renders and calls the API | 2 | ✅ | [`frontend/src/main.js`](final-devops-project/application/frontend/src/main.js) calls `/api/info`, `/api/customers`, `/api/entries` |
| Responsive, usable UI | 1 | ✅ | [desktop](screenshots/app-compose-desktop.png) and [mobile](screenshots/app-compose-mobile.png) screenshots |

## M2 — Testing (10)

| Criterion | Pts | Status | Evidence |
|---|---:|---|---|
| `pytest` runs without errors | 3 | ✅ | `17 passed in 0.62s` (Python 3.12, 2026-10-16); also job 1 of every CI run |
| ≥ 5 tests covering ≥ 3 endpoints | 4 | ✅ | 17 tests in [`tests/test_api.py`](final-devops-project/application/backend/tests/test_api.py) cover `/health`, `/ready`, `/metrics`, all `/api/entries` routes, `/api/customers` |
| Test DB or mock, not production | 2 | ✅ | [`tests/conftest.py`](final-devops-project/application/backend/tests/conftest.py): new SQLite file per test via `dependency_overrides` |
| `pytest.ini` / `conftest.py` configured | 1 | ✅ | [`pytest.ini`](final-devops-project/application/backend/pytest.ini) + `conftest.py` |

Extra: `flake8` is clean and CI fails under 80 % coverage (current: 92.9 %).

## M3 — Git and GitHub (5)

| Criterion | Pts | Status | Evidence |
|---|---:|---|---|
| Public repository | 2 | ✅ | <https://github.com/milap1afk/devops-homework> (public) |
| Meaningful commit messages | 2 | ✅ | e.g. "Session 21 incident fix: patient Postgres liveness probe, probe timeouts configurable, HPA max 3 on minikube"; 20+ commits |
| `.gitignore` excludes `.env`, `__pycache__`, `node_modules`, `.venv` | 1 | ✅ | [`../.gitignore`](../.gitignore) (`__pycache__/` and `.venv/` added with this file; stray `.pyc` files removed from Git) |

## M4 — Docker (10)

| Criterion | Pts | Status | Evidence |
|---|---:|---|---|
| `backend/Dockerfile` builds | 2 | ✅ | [`backend/Dockerfile`](final-devops-project/application/backend/Dockerfile); built by Compose and CI |
| Frontend multi-stage (Node build → Nginx) | 3 | ✅ | [`frontend/Dockerfile`](final-devops-project/application/frontend/Dockerfile): `node:22-alpine` → `nginx-unprivileged` |
| Images run as non-root | 2 | ✅ | backend `USER 10001`, frontend `USER 101` |
| `docker compose up --build` starts frontend, backend, postgres | 3 | ✅ | [`../compose-up-build.txt`](compose-up-build.txt), [`../screenshots/compose.png`](screenshots/compose.png); app at `localhost:3000` |

## M5 — CI/CD (15)

| Criterion | Pts | Status | Evidence |
|---|---:|---|---|
| Workflow file in `.github/workflows/` | 1 | ✅ | [`../.github/workflows/s21-final.yml`](../.github/workflows/s21-final.yml) |
| Triggers on push to `main` | 1 | ✅ | `on: push: branches: [main]` |
| pytest job fails the build on failure | 3 | ✅ | job 1; every later job `needs` it |
| Frontend built in the pipeline | 2 | ✅ | job 1: `npm ci && npm run build` |
| Images built for both tiers | 3 | ✅ | job 6 (matrix: backend, frontend) |
| Images pushed to GHCR | 3 | ✅ | job 9: `ghcr.io/milap1afk/kirana-{backend,frontend}` |
| Tags use the commit SHA, not `latest` | 2 | ✅ | `TAG: ${{ github.sha }}` |

Green run: <https://github.com/milap1afk/devops-homework/actions/runs/37605411031> (13/13 jobs, commit `d00093d`).
Still to add: a screenshot of the GHCR package page showing the SHA tags.

## M6 — DevSecOps (5)

| Criterion | Pts | Status | Evidence |
|---|---:|---|---|
| Trivy scans both images in CI | 3 | ✅ | job 7 (matrix); also Trivy fs (job 3) and Trivy config (job 5) |
| Fails on HIGH/CRITICAL | 1 | ✅ | [`security/trivy.yaml`](final-devops-project/security/trivy.yaml): `severity: [CRITICAL, HIGH]`, `exit-code: 1`, `ignore-unfixed: true` |
| Can explain a CVE or a clean result | 1 | ✅ | below |

**What Trivy scanned and what the result means.** Trivy unpacked both images and checked every OS package
(Debian 13.7 in the backend, Alpine 3.23.4 in the frontend) and every Python package against its vulnerability
database. The latest run found **0 HIGH/CRITICAL vulnerabilities that have a fix**, so the gate passed. That is
partly by design: both Dockerfiles upgrade OS packages at build time. "Clean" only means no known, fixable
issue today; unfixed CVEs are ignored on purpose, and a new CVE can appear tomorrow, which is why the scan runs on
every push.

## M7 — Terraform (15)

| Criterion | Pts | Status | Evidence |
|---|---:|---|---|
| `terraform/` with valid HCL | 2 | ✅ | `terraform validate` → "Success!" in [`terraform/output.txt`](final-devops-project/terraform/output.txt); also CI job 5 |
| `terraform init` succeeds | 1 | ✅ | same file |
| `terraform plan` non-empty, no errors | 2 | ✅ | **Plan: 26 to add** (offline plan, dummy credentials) |
| VPC with ≥ 2 public subnets **provisioned** | 3 | ⚠️ | coded in [`network.tf`](final-devops-project/terraform/network.tf) (2 public + 2 private); not applied to AWS |
| EKS with ≥ 1 node group **provisioned** | 4 | ⚠️ | coded in [`eks.tf`](final-devops-project/terraform/eks.tf) (`t3.medium`, 2–4 nodes); not applied |
| `terraform destroy` cleans up | 2 | ❌ | needs a real apply first |
| `terraform.tfvars.example`, no credentials committed | 1 | ✅ | [`terraform.tfvars.example`](final-devops-project/terraform/terraform.tfvars.example); Gitleaks job passes |

Missing: AWS Console screenshot (VPC + EKS in `ap-south-1`) and the `terraform destroy` output.
Cost warning: EKS control plane + NAT gateway + 2 `t3.medium` nodes are billed per hour. Apply, screenshot, destroy
the same day.

## M8 — Kubernetes + Helm (15)

| Criterion | Pts | Status | Evidence |
|---|---:|---|---|
| `k8s/namespace.yaml` applies | 1 | ✅ | [`k8s/namespace.yaml`](final-devops-project/k8s/namespace.yaml); applied by CI job 10 |
| Chart with `Chart.yaml`, `values.yaml`, templates | 3 | ✅ | [`helm/kirana`](final-devops-project/helm/kirana); `helm lint` in CI job 5 |
| `helm upgrade --install` succeeds | 3 | ✅ | CI job 10 (`--wait`, kind cluster) |
| Backend and frontend ≥ 2 replicas each | 2 | ✅ | HPA `minReplicas: 2` for both; CI log lists 2 + 2 Pods `Running` |
| ClusterIP Services for both | 2 | ✅ | `backend.yaml`, `frontend.yaml` |
| Ingress: `/` → frontend, `/api` → backend | 2 | ⚠️ | [`ingress.yaml`](final-devops-project/helm/kirana/templates/ingress.yaml) is correct; no browser screenshot through `kirana.local` yet |
| All Pods `Running` | 2 | ✅ | CI job 10 log (`kubectl get pods`) |

Missing: screenshots of `kubectl get pods -n kirana`, `kubectl get svc -n kirana`, `helm list -n kirana`, and the
app opened at `http://kirana.local`. The CI log has the same output as text, but the rubric asks for screenshots.

## M9 — Observability (10)

| Criterion | Pts | Status | Evidence |
|---|---:|---|---|
| `/metrics` returns Prometheus format | 2 | ✅ | `http_requests_total{handler="/api/info",...}` (re-checked 2026-10-16); `test_metrics_endpoint` |
| Prometheus installed and scraping the app | 3 | ⚠️ | [`servicemonitor.yaml`](final-devops-project/helm/kirana/templates/servicemonitor.yaml) ready; no Targets page screenshot showing Kirana `UP` |
| Grafana installed and reachable | 2 | ✅ | same stack and values as Session 20: [Session 20 screenshots](../session-20-monitoring-gitops/screenshots) |
| Grafana panel with live app metrics | 3 | ⚠️ | 6-panel dashboard in [`dashboards/kirana.json`](final-devops-project/helm/kirana/dashboards/kirana.json); no screenshot with data yet |

## M10 — Presentation + documentation (5)

| Criterion | Pts | Status | Evidence |
|---|---:|---|---|
| `README.md` explains the application | 2 | ✅ | [README.md](README.md) |
| Live demo: commit → pipeline → deployment updates | 3 | ⚠️ | script in [student-guide.md](student-guide.md#4-final-demo-script); to be done at the presentation |

---

## Submission checklist (from the rubric)

```text
Application
  [x] GitHub repository URL submitted          https://github.com/milap1afk/devops-homework
  [x] Application runs via docker compose up --build
  [x] At least 4 REST API endpoints implemented (11)
  [x] Alembic migration file present

Testing
  [x] pytest passes                            17 passed (add a screenshot of pytest -v)
  [x] At least 5 test cases present

Docker
  [x] backend/Dockerfile builds
  [x] frontend/Dockerfile uses multi-stage build
  [x] Non-root user in both Dockerfiles

CI/CD
  [x] GitHub Actions workflow present
  [x] Pipeline runs on push to main
  [x] pytest runs in pipeline
  [x] Images pushed to GHCR with SHA tags      (add GHCR package page screenshot)

Security
  [x] Trivy scan in pipeline
  [x] No secrets committed to Git              (Gitleaks job passes)

Terraform
  [x] terraform plan output submitted          (offline plan)
  [ ] VPC + EKS provisioned (AWS Console screenshot)
  [ ] terraform destroy output submitted

Kubernetes + Helm
  [ ] kubectl get pods screenshot (all Running)
  [ ] helm list screenshot
  [ ] Application accessible via Ingress

Observability
  [x] /metrics endpoint                        (add curl screenshot)
  [ ] Prometheus Targets page screenshot (UP)
  [ ] Grafana dashboard screenshot

Documentation
  [x] README.md present
  [ ] Presentation completed or recording submitted
```

## Grading policy (from the course)

- Late submissions lose 5 points per 24 hours after the deadline.
- Copying another student, or cloning TaskBoard without meaningful changes, scores zero. Kirana Ledger is its own
  domain (credit ledger, honorific-free customer names, Hindi reminders), its own API and its own frontend; only
  the DevOps architecture follows TaskBoard, which the rules allow.
- AWS costs are the student's responsibility: run `terraform destroy` after evaluation.
