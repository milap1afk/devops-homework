# VPC: Virtual Private Cloud (Networking)

## What is VPC?
A **logically isolated private network** in an AWS region, which works like your own data-centre network in the cloud.
You choose the IP range, split it into subnets, control routing, and decide what can reach the internet. Every account
gets a **default VPC** per region, but production uses custom VPCs (usually built with Terraform, as in Session 19).

```text
VPC 10.0.0.0/16  (ap-south-1)
├── AZ ap-south-1a
│   ├── Public subnet  10.0.1.0/24   ── route 0.0.0.0/0 → Internet Gateway   [ALB, NAT GW, bastion]
│   └── Private subnet 10.0.11.0/24  ── route 0.0.0.0/0 → NAT Gateway        [app servers]
├── AZ ap-south-1b
│   ├── Public subnet  10.0.2.0/24
│   └── Private subnet 10.0.12.0/24                                           [RDS standby]
└── Internet Gateway  ◄──►  Internet
```

## CIDR
**Classless Inter-Domain Routing** notation `IP/prefix` describes a range of addresses. The prefix is how many leading bits are fixed.

| CIDR | Addresses | Use |
|---|---|---|
| `10.0.0.0/16` | 65,536 | whole VPC (allowed range is /16 to /28) |
| `10.0.1.0/24` | 256 (**251 usable**) | one subnet |
| `10.0.1.0/28` | 16 (11 usable) | smallest subnet |
| `203.0.113.4/32` | 1 | a single IP, e.g. "my laptop" in a security group |

AWS reserves **5 IPs per subnet** (network, VPC router, DNS, future use, broadcast). Use private ranges (RFC 1918:
`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) and **don't overlap** with networks you may need to peer or VPN to.

## Subnets
- A slice of the VPC's CIDR, living in **exactly one Availability Zone**.
- Spread subnets across **2–3 AZs** for high availability.
- A subnet is "public" or "private" purely because of its **route table** (see below).

## Route tables
- A set of rules: **destination CIDR → target**. Every subnet is associated with exactly one route table.
- Every table has the implicit `local` route (`10.0.0.0/16 → local`), so all subnets in a VPC can reach each other.
- Public: `0.0.0.0/0 → igw-xxxx`. Private: `0.0.0.0/0 → nat-xxxx`. Other targets: peering, Transit Gateway, VPN, VPC endpoints.

## Internet Gateway (IGW)
- A horizontally scaled, highly available gateway attached to the VPC (one per VPC). It allows **two-way** internet traffic.
- It does 1:1 NAT between an instance's private IP and its public/Elastic IP.
- Needs both a route to it **and** a public IP on the instance.

## NAT Gateway
- Lets instances in **private** subnets make **outbound** connections (OS updates, external APIs) while **blocking inbound** connections from the internet.
- It lives in a **public** subnet with an Elastic IP. Private route tables send `0.0.0.0/0` to it.
- Managed and scales automatically, but **charged per hour + per GB**. Use one per AZ for HA, or a single one to save money in dev.
  For AWS services, **VPC endpoints** (Gateway endpoints for S3/DynamoDB are free) avoid NAT costs.

## Security Groups
- A **stateful** firewall at the **instance / network-interface** level, with **allow rules only**.
- Can reference other security groups ("DB allows 5432 from app-SG").
- Default: all inbound denied, all outbound allowed.

## Network ACLs (NACLs)
- A **stateless** firewall at the **subnet** level, with **allow and deny** rules evaluated **in number order** (lowest first).
- Because they're stateless, you must allow **return traffic** explicitly (ephemeral ports 1024–65535).
- The default NACL allows everything. Use NACLs for coarse subnet-wide blocks (deny a malicious IP range).

| | Security Group | Network ACL |
|---|---|---|
| Level | instance / ENI | subnet |
| State | **stateful** | **stateless** |
| Rules | allow only | allow + deny |
| Evaluation | all rules together | in order, first match wins |
| Default | deny in / allow out | allow all |

## Public vs private subnet

| | Public subnet | Private subnet |
|---|---|---|
| Default route | `0.0.0.0/0 → Internet Gateway` | `0.0.0.0/0 → NAT Gateway` (or none at all) |
| Inbound from internet | possible (with public IP + SG rule) | **not possible** |
| Outbound to internet | directly | via NAT |
| Put here | load balancers, NAT gateways, bastion | app servers, databases, EKS nodes, caches |

**Best practice:** only load balancers face the internet, and everything else lives in private subnets.
