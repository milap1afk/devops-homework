# Security tooling (used by `.github/workflows/s21-final.yml`)

| Stage | Tool | Config | Blocks on |
|---|---|---|---|
| SAST | Semgrep (`p/python`, `p/flask`, `p/dockerfile`, `p/secrets`) | [`.semgrepignore`](.semgrepignore) | any finding |
| SCA | pip-audit + Trivy fs | [`trivy.yaml`](trivy.yaml) | known vulnerable dependency (fixable HIGH/CRITICAL) |
| Secret scanning | Gitleaks (git history + files) | [`.gitleaks.toml`](.gitleaks.toml) | any secret |
| IaC scanning | Trivy config (Helm, K8s YAML, Terraform, Dockerfile) + `terraform validate` | [`trivy.yaml`](trivy.yaml) | HIGH/CRITICAL misconfiguration |
| Image scanning | Trivy image + SBOM | [`trivy.yaml`](trivy.yaml) | fixable HIGH/CRITICAL CVE |
| Security gate | `needs.*.result` | workflow | any of the above failing |
