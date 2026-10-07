# IAM: Identity and Access Management (Governance)

## What is IAM?
IAM is the AWS service that controls **who** (authentication) can do **what** (authorization) on **which** resources.
It's **global** (not tied to a region) and **free**. Every AWS API call is checked against IAM.

```text
Principal (user / role / service)  ──request──►  IAM policy evaluation  ──►  Allow / Deny
     "who"                          "s3:PutObject on arn:aws:s3:::bucket/*"
```

## Users
- A long-term identity for **one person or application**, with a console password and/or **access keys** (`AKIA…`).
- A new user has **no permissions** until a policy is attached.
- The **root user** (the account email) can do everything. Lock it away: enable MFA, never create root access keys, and don't use it day to day.

## Groups
- A collection of users. Attach policies to the **group**, not to each user (`Developers`, `Admins`, `ReadOnly`).
- Users can belong to several groups. Groups can't be nested and can't be principals in a policy.

## Roles
- An identity with permissions but **no long-term credentials**. Whoever *assumes* it gets **temporary credentials** from STS (they expire, typically after 1 hour).
- Every role has a **trust policy** (who may assume it) and **permission policies** (what it may do).
- Used by: **EC2 instance profiles**, Lambda execution roles, EKS Pods (IRSA / Pod Identity), cross-account access, SSO users, and GitHub Actions through **OIDC** (no stored keys).

## Policies
JSON documents that grant or deny permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "ReadOneBucket",
    "Effect": "Allow",
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": ["arn:aws:s3:::milap-devops-s3-demo-*", "arn:aws:s3:::milap-devops-s3-demo-*/*"],
    "Condition": { "Bool": { "aws:SecureTransport": "true" } }
  }]
}
```
| Type | Attached to | Example |
|---|---|---|
| AWS managed | users/groups/roles | `ReadOnlyAccess`, `AmazonS3FullAccess` |
| Customer managed | users/groups/roles | your own reusable JSON policy |
| Inline | exactly one identity | a one-off, deleted with the identity |
| Resource-based | the resource itself | S3 bucket policy, KMS key policy, role trust policy |
| Permission boundary / SCP | user, role / AWS Organization | **maximum** allowed permissions (guardrails) |

## Permissions: how a request is evaluated
1. Everything is **denied by default** (implicit deny).
2. An **explicit `Deny`** anywhere wins, always.
3. Otherwise the request is allowed only if some policy **explicitly `Allow`s** it, *and* no SCP or boundary blocks it.

## Least privilege
Grant **only** the actions and resources a job needs, nothing more. Start from zero and add.
- Scope `Resource` to specific ARNs, not `"*"`.
- Use conditions (source IP, MFA, tags, `aws:SecureTransport`).
- Check **IAM Access Analyzer** and "last accessed" data, and remove unused permissions.
- Example: a CI pipeline that uploads to one bucket gets `s3:PutObject` on `arn:aws:s3:::my-artifacts/*`, not `AmazonS3FullAccess`.

## IAM best practices
- Lock down the **root user**: MFA, no access keys, used only for billing/account tasks.
- **MFA for every human**, ideally through **IAM Identity Center (SSO)** instead of IAM users.
- Prefer **roles + temporary credentials** over long-lived access keys. If keys are unavoidable, **rotate** them and never commit them to Git.
- Manage permissions through **groups / roles**, not individual users.
- Apply **least privilege**, and use permission boundaries and SCPs as guardrails.
- Enable **CloudTrail** to audit every API call, and review the **credential report** regularly.
- Use a **strong password policy**.
- Manage IAM itself as code (Terraform `aws_iam_role`, `aws_iam_policy`).

## Common use cases
- Give developers read-only production access, and admins full access, through groups.
- An **EC2 instance role** so the app can read S3 or Secrets Manager without storing keys on the server.
- **GitHub Actions → AWS** through OIDC, assuming a deploy role scoped to one ECR repo and one EKS cluster.
- **Cross-account access**: a role in a prod account assumed from a tooling account.
- Bucket policies that allow only one role, or only traffic through a VPC endpoint.
