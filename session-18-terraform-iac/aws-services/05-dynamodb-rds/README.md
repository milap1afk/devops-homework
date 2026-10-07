# DynamoDB & RDS: Database Services

| | DynamoDB | RDS |
|---|---|---|
| Model | **NoSQL** key-value / document | **Relational** (SQL) |
| Schema | flexible, per item | fixed tables, columns, foreign keys |
| Scaling | automatic, horizontal, effectively unlimited | vertical (instance size) + read replicas |
| Management | **serverless**, nothing to patch | managed instances (you choose size, AWS patches) |
| Query | by key (plus indexes); no joins | full SQL, joins, transactions |
| Best for | huge scale, simple access patterns, low latency | complex queries, existing SQL apps, reporting |

---

# DynamoDB

## NoSQL
DynamoDB is a fully managed, **serverless NoSQL** database. It gives single-digit-millisecond reads and writes at any scale,
with no servers or connections to manage. You design around **access patterns** (how you'll query) instead of normalised tables.
Capacity modes: **on-demand** (pay per request) or **provisioned** (+ auto scaling).

## Tables
The top-level container for data, like a table in SQL but **without a fixed schema** beyond the primary key.
For example, a table `KiranaLedger`.

## Items
A single record, like a row: **up to 400 KB**. Items in the same table can have different attributes.
```json
{ "customer": "Ramesh", "entryTime": "2026-10-07T10:15:00Z", "type": "udhar", "amount": 500, "note": "atta + daal" }
```

## Attributes
The fields of an item, like columns. Types: String, Number, Binary, Boolean, Null, **List**, **Map** (nested JSON), and String/Number/Binary Sets.

## Partition key
- The **required** part of the primary key. DynamoDB **hashes** it to decide which physical partition stores the item.
- Choose a key with **many distinct values** that are accessed evenly (`customerId`, `orderId`). A key like `status = active` creates "hot" partitions.
- If it's the only key, it must be **unique per item**.

## Sort key
- The optional second part of a **composite primary key** (partition key + sort key must be unique together).
- Items with the same partition key are stored **sorted** by the sort key, which enables range queries:
  `customer = "Ramesh" AND entryTime BETWEEN "2026-10-01" AND "2026-10-31"`.
- Other access patterns use **GSIs** (Global Secondary Indexes) with a different partition/sort key, and **LSIs** (same partition key, different sort key).

## Use cases
- Shopping carts, user sessions, user profiles, game leaderboards.
- IoT and event data (huge write rates), ad tech, real-time bidding.
- Serverless apps with Lambda + API Gateway. Terraform state **locking** (classic `backend "s3"` + `dynamodb_table`).
- Global apps with **Global Tables** (multi-region active-active). Change capture with **DynamoDB Streams**, and caching with DAX.

---

# RDS

## Relational database
RDS (Relational Database Service) runs **managed SQL databases**. AWS handles provisioning, OS and DB patching, backups,
monitoring and failover. You handle schema, queries, indexes and sizing. Data lives in tables with rows, columns, keys,
**joins** and **ACID transactions**.

## Supported engines
**MySQL**, **PostgreSQL**, **MariaDB**, **Oracle**, **Microsoft SQL Server**, **IBM Db2**, and **Amazon Aurora**
(MySQL- and PostgreSQL-compatible, cloud-native storage that replicates 6 copies across 3 AZs, faster, with Aurora Serverless v2 autoscaling).

## DB instances
- The managed database server: an **instance class** (`db.t4g.micro` for free-tier testing, `db.m7g.large`, `db.r7g.xlarge` for memory-heavy loads) plus storage
  (**gp3** or **io2**, with storage autoscaling).
- Launched into a **DB subnet group** (private subnets in at least 2 AZs). Reached by an **endpoint** DNS name, not an IP.
- Configured with **parameter groups** (engine settings) and **option groups**.

## Security
- Run in **private subnets**, `publicly_accessible = false`.
- **Security group** allows the DB port (3306/5432) only from the app servers' security group.
- **Encryption at rest** with KMS (must be chosen at creation; snapshots are encrypted too). **TLS in transit** (`rds.force_ssl`).
- Credentials in **Secrets Manager** with automatic rotation (`manage_master_user_password = true`), or **IAM database authentication** (no passwords at all).
- Audit with CloudTrail, enhanced monitoring, Performance Insights and database activity streams.

## Backups
- **Automated backups:** daily snapshot + transaction logs, kept 1–35 days. This allows **point-in-time restore** to any second in that window.
- **Manual snapshots:** kept until you delete them. They can be copied to other regions or accounts for DR.
- A restore always creates a **new** DB instance (new endpoint).

## Multi-AZ
- **High availability**: a **synchronous standby** copy in another AZ. If the primary fails, or during maintenance, RDS **fails over automatically**
  (about 60–120 s) by moving the same endpoint DNS name to the standby.
- The standby **can't serve reads** in the classic setup. The newer **Multi-AZ DB cluster** has 2 readable standbys.
- It's about **availability**, not read scaling.

## Read replicas
- **Asynchronous** copies (up to 15 for most engines) with their **own endpoints**, for **scaling reads** (reports, analytics, read-heavy APIs).
- Can be in another **region** (cross-region DR), and can be **promoted** to a standalone primary.
- Replication lag means reads can be slightly stale.

| | Multi-AZ | Read replica |
|---|---|---|
| Goal | HA / failover | read scaling |
| Replication | synchronous | asynchronous |
| Serves reads? | no (classic) | yes |
| Endpoint | same as primary | separate |

## Use cases
- Web and mobile backends that need relational data (users, orders, payments). E-commerce, CRM, ERP.
- Lift-and-shift of existing MySQL, PostgreSQL, Oracle or SQL Server apps without managing DB servers.
- Reporting and BI on read replicas.
- A Kirana-style ledger at scale: PostgreSQL with tables `customers` and `entries` (a foreign key) and a `SUM(amount)` balance query.
