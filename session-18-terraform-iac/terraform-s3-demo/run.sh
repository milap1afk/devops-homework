#!/usr/bin/env bash
# Runs the offline part of the Terraform workflow and records output.txt.
# No AWS account is used: dummy credentials + skip_* flags let `plan` run without calling AWS.
cd "$(dirname "$0")"
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }
export AWS_ACCESS_KEY_ID=offline-plan-dummy-id AWS_SECRET_ACCESS_KEY=offline-plan-dummy-secret TF_IN_AUTOMATION=1
export TF_CLI_ARGS="-no-color" CHECKPOINT_DISABLE=1
{
run 'terraform version'
run 'terraform init'
run 'terraform fmt -check -diff -recursive && echo "fmt: all files already formatted"'
run 'terraform validate'
echo "# Validation catches bad input before any API call:"
run 'terraform validate && terraform plan -var bucket_prefix=Bad_Name! -input=false 2>&1 | sed -n "/Error/,/bucket_prefix must/p"'
run 'terraform plan -input=false -out=s3.tfplan'
run 'terraform show s3.tfplan | head -40'
run 'terraform show -json s3.tfplan | python3 -c "import json,sys; p=json.load(sys.stdin); [print(r[\"change\"][\"actions\"][0].ljust(7), r[\"address\"]) for r in p[\"resource_changes\"]]"'
run 'terraform graph | grep -- "->" | grep -v provider | sed "s/\[label.*//"'
} > output.txt 2>&1
rm -f s3.tfplan
