# Session 18: Terraform & Infrastructure as Code

## Task 1: Terraform S3 demo → [`terraform-s3-demo/`](terraform-s3-demo)

```text
terraform-s3-demo/
├── main.tf            ├── outputs.tf        ├── terraform.tfvars
├── variables.tf       ├── provider.tf       └── README.md   ← full workflow documentation
```

Creates a private, versioned, encrypted S3 bucket with a lifecycle rule and a sample object (7 resources).
`init` → `fmt` → `validate` → `plan` were **run for real** (`Plan: 7 to add, 0 to change, 0 to destroy`).
No AWS account is configured on this machine, so `apply` / `show` / `output` / `destroy` are documented with their commands
and expected results, and no AWS resources were created. Details: [`terraform-s3-demo/README.md`](terraform-s3-demo/README.md).

![terraform](screenshots/terraform-s3-demo.png)

## Task 2: AWS services research → [`aws-services/`](aws-services)

| # | Service | Category | README |
|---|---|---|---|
| 01 | IAM | Governance | [`aws-services/01-iam/README.md`](aws-services/01-iam/README.md) |
| 02 | EC2 | Compute | [`aws-services/02-ec2/README.md`](aws-services/02-ec2/README.md) |
| 03 | S3 | Storage | [`aws-services/03-s3/README.md`](aws-services/03-s3/README.md) |
| 04 | VPC | Networking | [`aws-services/04-vpc/README.md`](aws-services/04-vpc/README.md) |
| 05 | DynamoDB & RDS | Databases | [`aws-services/05-dynamodb-rds/README.md`](aws-services/05-dynamodb-rds/README.md) |
