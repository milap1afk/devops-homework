#!/usr/bin/env bash
# Offline Terraform workflow -> output.txt. No AWS account is used and nothing is created.
cd "$(dirname "$0")"
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }
export AWS_ACCESS_KEY_ID=offline-plan-dummy-id AWS_SECRET_ACCESS_KEY=offline-plan-dummy-secret
export TF_IN_AUTOMATION=1 TF_CLI_ARGS="-no-color" CHECKPOINT_DISABLE=1
{
run 'terraform init | grep -E "Installed|successfully"'
run 'terraform fmt -check -recursive && echo "fmt: OK"'
run 'terraform validate'
run 'terraform plan -input=false -var-file=terraform.tfvars.example -out=final.tfplan | grep -E "^  # |^Plan:"'
} > output.txt 2>&1
rm -f final.tfplan
