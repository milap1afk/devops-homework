#!/usr/bin/env bash
# Offline part of the workflow -> output.txt. No AWS account is used and nothing is created.
cd "$(dirname "$0")"
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }
export AWS_ACCESS_KEY_ID=AKIAOFFLINEPLANONLY00 AWS_SECRET_ACCESS_KEY=offline-plan-dummy-secret
export TF_IN_AUTOMATION=1 TF_CLI_ARGS="-no-color" CHECKPOINT_DISABLE=1
{
run 'terraform init'
run 'terraform fmt -check -recursive && echo "fmt: OK"'
run 'terraform validate'
run 'terraform plan -input=false -out=infra.tfplan | grep -E "^  # |^Plan:|will be (created|read)"'
run 'terraform show -json infra.tfplan | python3 -c "import json,sys; p=json.load(sys.stdin); [print(r[\"change\"][\"actions\"][0].ljust(7), r[\"address\"]) for r in p[\"resource_changes\"]]"'
echo "# Selected values from the plan:"
run "terraform show -json infra.tfplan | python3 -c \"import json,sys; p=json.load(sys.stdin); v={r['address']:r['change']['after'] for r in p['resource_changes']}; print('vpc cidr      :', v['aws_vpc.main']['cidr_block']); print('subnet        :', v['aws_subnet.public']['cidr_block'], v['aws_subnet.public']['availability_zone'], 'public_ip_on_launch=', v['aws_subnet.public']['map_public_ip_on_launch']); print('route         :', [r['cidr_block'] + ' -> internet gateway (id known after apply)' for r in v['aws_route_table.public']['route']]); print('instance      :', v['aws_instance.web']['instance_type'], 'IMDSv2=', v['aws_instance.web']['metadata_options'][0]['http_tokens'], 'root gp3', v['aws_instance.web']['root_block_device'][0]['volume_size'], 'GB encrypted=', v['aws_instance.web']['root_block_device'][0]['encrypted']); print('ssh rule      :', v['aws_vpc_security_group_ingress_rule.ssh']['cidr_ipv4'], 'port', v['aws_vpc_security_group_ingress_rule.ssh']['from_port'])\""
echo "# Dependency graph (who waits for whom):"
run 'terraform graph | grep -- "->" | grep -v -E "provider|\[root\]" | sed -E "s/\[label.*//; s/^[[:space:]]+//" | sort'
echo "# State: nothing has been applied, so the state is empty"
run 'terraform state list || true'
} > output.txt 2>&1
rm -f infra.tfplan
