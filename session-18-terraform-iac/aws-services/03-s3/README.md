# S3: Simple Storage Service (Storage)

## What is S3?
**Object storage** with practically unlimited capacity, accessed over HTTPS/API instead of mounted like a disk.
Designed for **99.999999999% (11 nines) durability**: data is stored across at least 3 Availability Zones. You pay per GB stored, per request and for data out.
It's what [`../../terraform-s3-demo`](../../terraform-s3-demo) creates.

## Buckets
- A top-level **container** for objects, created in **one region**.
- Names are **globally unique** across all AWS accounts, 3–63 characters, lowercase, DNS-compatible. (That's why the demo adds a random suffix.)
- Bucket-level settings: versioning, encryption, lifecycle, policies, logging, replication, static website hosting.
- **Block Public Access** is on by default for new buckets. Keep it on unless you are deliberately hosting public files.

## Objects
- A **file + metadata**, identified by a **key** (`invoices/2026/10/inv-1001.pdf`). The "folders" are just key prefixes, because S3 is flat.
- Up to **5 TB** per object. Uploads over 100 MB should use **multipart upload**.
- Each object has metadata (`Content-Type`, custom `x-amz-meta-*`), tags, an ETag, and a storage class.
- Strong read-after-write consistency.

## Storage classes

| Class | For | Retrieval |
|---|---|---|
| **S3 Standard** | frequently accessed data | instant |
| **S3 Intelligent-Tiering** | unknown or changing access; moves objects between tiers automatically | instant |
| **Standard-IA** / **One Zone-IA** | infrequent access (monthly); One Zone = a single AZ, cheaper | instant, per-GB retrieval fee |
| **Glacier Instant Retrieval** | archive read about once a quarter | milliseconds |
| **Glacier Flexible Retrieval** | archive | minutes to hours |
| **Glacier Deep Archive** | long-term compliance (7–10 years) | up to 12 hours, cheapest |
| **S3 Express One Zone** | ultra-low-latency, single AZ | single-digit ms |

## Versioning
- Keeps **every version** of every object. An overwrite creates a new version, and a delete adds a *delete marker*, which can be undone.
- Protects against accidental deletes and overwrites, and against ransomware (especially with **MFA Delete** or **Object Lock**).
- Once enabled it can only be **suspended**, never fully turned off. Old versions cost storage, so pair it with lifecycle rules.
- Required for **replication** (CRR/SRR).

## Lifecycle policies
Rules that automatically **move** or **delete** objects by age, prefix or tag:
```text
logs/*  → Standard-IA after 30 days → Glacier after 90 days → delete after 365 days
noncurrent versions → delete 30 days after they become old   (the demo does this)
incomplete multipart uploads → abort after 7 days
```

## Encryption
- **At rest:** every new object is encrypted by default (since January 2023).
  - **SSE-S3** (`AES256`): S3-managed keys, the default, used in the demo.
  - **SSE-KMS**: keys in AWS KMS, with key policies, rotation and a CloudTrail record of every use. Use **bucket keys** to cut KMS cost.
  - **DSSE-KMS** (dual layer) and **SSE-C** (you supply the key on each request).
  - **Client-side**: encrypt before uploading.
- **In transit:** HTTPS/TLS. Enforce it with a bucket policy that denies requests where `aws:SecureTransport` is `false`.

## Bucket policies
A **resource-based JSON policy** on the bucket that controls who can do what, including other accounts or the public:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Sid": "DenyInsecureTransport", "Effect": "Deny", "Principal": "*", "Action": "s3:*",
      "Resource": ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"],
      "Condition": { "Bool": { "aws:SecureTransport": "false" } } },
    { "Sid": "AppRoleRead", "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::123456789012:role/app-role" },
      "Action": "s3:GetObject", "Resource": "arn:aws:s3:::my-bucket/*" }
  ]
}
```
Access is allowed only if IAM policy **and/or** bucket policy allow it, and nothing denies it. ACLs are legacy and disabled by default ("Bucket owner enforced").
Use **pre-signed URLs** for temporary access to private objects.

## Common use cases
- Backups and disaster recovery, log archives, data lakes (queried with Athena/EMR), ML datasets.
- **Static website** hosting (React builds) behind **CloudFront**.
- Build artifacts and Terraform **remote state** (`backend "s3"` with locking).
- User uploads (images, documents) through pre-signed URLs.
- Media storage and distribution, and compliance archives with Object Lock (WORM).
