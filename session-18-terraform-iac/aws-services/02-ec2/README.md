# EC2: Elastic Compute Cloud (Compute)

## What is EC2?
**Virtual servers ("instances") in the cloud**, rented by the second. You pick the OS, CPU/RAM, disk and network.
AWS runs the hardware, and you manage everything from the OS up (patching, software, security). It's the basic AWS
compute service and sits underneath many others (EKS nodes, ECS on EC2, EMR).

## AMI (Amazon Machine Image)
- The **template** an instance boots from: OS + pre-installed software + launch permissions + root volume snapshot.
- Sources: AWS (Amazon Linux 2023, Ubuntu, Windows), the **Marketplace** (pre-built software), or **your own** (bake one from a configured instance or with Packer).
- AMIs are **regional**, so copy them to use in another region. "Golden AMIs" speed up auto-scaling boots.

## Instance types
Named `family + generation + options . size`, for example **`t3.micro`**, **`m7g.large`** (`g` = Graviton/ARM).

| Family | Optimised for | Examples |
|---|---|---|
| **T** (burstable) | low/variable CPU, uses CPU credits | `t3.micro` (free tier), `t4g.small` |
| **M** (general purpose) | balanced CPU/RAM | `m7i.large` |
| **C** (compute) | high CPU | `c7g.xlarge` (batch, encoding) |
| **R / X** (memory) | lots of RAM | `r7i.2xlarge` (databases, caches) |
| **I / D** (storage) | fast local NVMe | `i4i.large` |
| **P / G / Inf / Trn** (accelerated) | GPUs / ML chips | `g5.xlarge` |

**Pricing models:** On-Demand (pay as you go), **Savings Plans / Reserved** (1–3 year commitment, up to ~72% off),
**Spot** (spare capacity, up to ~90% off, can be reclaimed with 2 minutes' notice), Dedicated Hosts.

## Key pairs
- An **SSH public/private key pair**. AWS puts the **public** key on the instance (`~/.ssh/authorized_keys`), and you keep the **private** `.pem` file.
- `ssh -i mykey.pem ec2-user@<public-ip>` (`ubuntu@` for Ubuntu). Run `chmod 400 mykey.pem` first.
- Losing the private key means losing SSH access. Better: **SSM Session Manager**, a shell with no open port 22 and no keys.

## Security Groups
- A **stateful virtual firewall** attached to an instance's network interface.
- **Allow rules only** (no deny). Inbound is denied by default and outbound is allowed by default.
- **Stateful**: if inbound port 443 is allowed, the reply traffic is automatically allowed back out.
- A source can be a CIDR (`203.0.113.4/32`) **or another security group** ("allow 3306 from the app-servers SG").
- Example: web SG allows 80/443 from `0.0.0.0/0` and 22 only from my IP. DB SG allows 3306 only from the web SG.

## EBS (Elastic Block Store)
- **Network-attached block disks** for instances. They persist independently of the instance (unless *delete on termination* is set).
- An EBS volume lives in **one Availability Zone** and usually attaches to one instance.
- Types: **gp3** (general SSD, default), **io2** (provisioned IOPS for databases), **st1/sc1** (HDD throughput/cold).
- **Snapshots** are incremental backups stored in S3. Use them to restore, copy across regions, or create AMIs.
- Encrypt with KMS (set "encryption by default" on the account).
- Different from **instance store**: fast, local, *ephemeral* disk that is lost on stop or termination.

## Public vs private IP

| | Private IP | Public IP | Elastic IP |
|---|---|---|---|
| From | the subnet's CIDR (`10.0.1.25`) | AWS pool, auto-assigned in public subnets | allocated to your account |
| Reachable from | inside the VPC (and peered/VPN networks) | the internet (through an Internet Gateway) | the internet |
| On stop/start | **kept** | **changes** | **kept** (static) |
| Cost | free | charged per hour (IPv4) | charged per hour |

The instance's OS only sees its private IP. The Internet Gateway translates public ↔ private (1:1 NAT).

## Instance lifecycle
```text
          launch
            │
            ▼
        pending ──► running ◄──────── start ───┐
                      │  │ reboot (same host,   │
                      │  │  keeps IPs & disk)    │
                 stop │  └────────────────────►─┘
                      ▼                          │
                  stopping ──► stopped ──────────┘   (EBS kept; no compute charge;
                      │                               public IP released)
            terminate │  (or hibernate: RAM saved to EBS)
                      ▼
               shutting-down ──► terminated  (gone; root EBS deleted by default)
```
- Billing runs only in **running** (EBS storage is billed even while stopped).
- **User data** scripts run on first boot (install packages, join a cluster).

## Common use cases
- Web/app servers in an **Auto Scaling Group** behind an **Application Load Balancer**.
- Bastion/jump hosts (better replaced by SSM), CI build runners, self-hosted databases.
- Kubernetes worker nodes (EKS managed node groups), batch/HPC jobs on Spot, GPU ML training.
- Lift-and-shift migration of on-prem VMs.
