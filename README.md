# DevOps Homework

Homework for the DevOps course: one folder per session, each with its own `README.md`
(commands, real outputs, screenshots and explanations).

Everything was run locally on a MacBook Air (Apple Silicon, 8 GB RAM): **Colima** (Docker engine), **minikube v1.37**
(Kubernetes 1.37), **Helm v4.3**, **Terraform v1.16** and **GitHub Actions** for CI/CD.

| Session | Topic | README |
|---|---|---|
| 1 & 2 | Linux Fundamentals | [session-01-02-linux](session-01-02-linux/README.md) |
| 3 | Shell Scripting | [session-03-shell-scripting](session-03-shell-scripting/README.md) |
| 4 | Networking | [session-04-networking](session-04-networking/README.md) |
| 5 | Git and GitHub | [session-05-git](session-05-git/README.md) |
| 6 | Docker Fundamentals | [session-06-docker-fundamentals](session-06-docker-fundamentals/README.md) |
| 7 | Docker Images (multi-stage) | [session-07-docker-images](session-07-docker-images/README.md) |
| 8 | Docker Networking & Volumes | [session-08-docker-networking](session-08-docker-networking/README.md) |
| 9 | Kubernetes Fundamentals | [session-09-k8s-fundamentals](session-09-k8s-fundamentals/README.md) |
| 10 | Pods, ReplicaSets & Deployments | [session-10-k8s-deployments](session-10-k8s-deployments/README.md) |
| 11 | Networking & Services | [session-11-k8s-services](session-11-k8s-services/README.md) |
| 12 | Ingress, ConfigMaps & Secrets | [session-12-k8s-ingress-configmaps-secrets](session-12-k8s-ingress-configmaps-secrets/README.md) |
| 13 | Storage, HPA & Probes | [session-13-k8s-storage-hpa-probes](session-13-k8s-storage-hpa-probes/README.md) |
| 14 | Kubernetes Troubleshooting | [session-14-k8s-troubleshooting](session-14-k8s-troubleshooting/README.md) |
| 15 | Helm | [session-15-helm](session-15-helm/README.md) |
| 16 | CI/CD & GitHub Actions | [session-16-cicd-github-actions](session-16-cicd-github-actions/README.md) |
| 17 | Complete CI/CD & DevSecOps | [session-17-devsecops](session-17-devsecops/README.md) |
| 18 | Terraform & IaC | [session-18-terraform-iac](session-18-terraform-iac/README.md) |
| 19 | Cloud & Terraform in Action | [session-19-terraform-cloud](session-19-terraform-cloud/README.md) |
| 20 | Monitoring, Observability & GitOps | [session-20-monitoring-gitops](session-20-monitoring-gitops/README.md) |
| 21 | Final DevOps Project | [session-21-final-devops-project](session-21-final-devops-project/README.md) |

[`tools/shot.sh`](tools/shot.sh) renders captured terminal output as the PNG "screenshots" used in the READMEs.
Each session folder has a `demo.sh` / `run.sh` that reproduces its outputs.
