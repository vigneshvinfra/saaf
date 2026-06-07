# Compliance control mapping

Every requirement from the service spec, mapped to the control that satisfies it
and where it lives in this repo.

## Encryption at rest (KMS) — all data stores

| Store | Control | Where |
| --- | --- | --- |
| RDS Postgres | `storage_encrypted` + customer KMS key; PI + master secret KMS-encrypted | `modules/data-stores/rds.tf` |
| S3 borrower docs | SSE-KMS (data CMK), bucket-key | `modules/data-stores/s3.tf` |
| S3 audit | SSE-KMS (separate audit CMK) | `modules/data-stores/s3.tf` |
| DynamoDB | SSE with KMS CMK | `modules/data-stores/dynamodb.tf` |
| EKS secrets | `cluster_encryption_config` (envelope) | `modules/eks/main.tf` |
| Control-plane logs | KMS-encrypted log group | `modules/eks/main.tf` |
| Terraform state | KMS-encrypted S3 bucket | `terraform/bootstrap/main.tf` |
| Secrets Manager | CMK-encrypted | `modules/secrets/main.tf` |

All CMKs have `enable_key_rotation = true` (annual).

## Encryption in transit (TLS 1.2+)

| Path | Control | Where |
| --- | --- | --- |
| Caller → service | ALB HTTPS listener, `ELBSecurityPolicy-TLS13-1-2-2021-06` | `deploy/chart/.../ingress.yaml`, `values-*.yaml` |
| Pod → AWS APIs | Interface VPC endpoints (TLS), private DNS | `modules/network/main.tf` |
| Any → S3 | Bucket policy denies `aws:SecureTransport=false` | `modules/data-stores/s3.tf` |
| Any → state bucket | Same deny-non-TLS policy | `terraform/bootstrap/main.tf` |

## 7-year auditable LLM-call trail

- **WORM storage:** S3 Object Lock, **COMPLIANCE mode, 7-year** default
  retention — records cannot be modified or deleted before expiry, by anyone
  including root. Versioned, KMS-encrypted, lifecycle-tiered to Glacier.
  → `modules/data-stores/s3.tf`
- **What's captured:** the agent's `write_audit_record` persists input, output,
  model, timestamp, loan_id, item_id, latency (see `src/agent/store.py`); the
  IAM principal is captured via CloudTrail data events on the bucket + the pod's
  Pod Identity role. The agent has **append-only** (`s3:PutObject`) access — no
  delete/overwrite. → `modules/agent-identity/main.tf`

## Least-privilege IAM (service identity)

- Agent runs as a dedicated ServiceAccount bound via **EKS Pod Identity** to a
  role whose every statement targets a specific ARN — read docs, append audit,
  idempotency table, its own secrets, one Bedrock model, send-as one SES
  address. No `*` resources, no broad service grants.
  → `modules/agent-identity/main.tf`
- Platform identities (LB controller, EBS CSI, Karpenter) likewise scoped via
  Pod Identity. CI uses GitHub **OIDC** roles (ECR-push / TF-plan) — no static
  keys. → `modules/platform-addons`, `modules/karpenter`, `terraform/global`

## Secret rotation (quarterly minimum)

- **DB credentials:** RDS-managed master password, auto-rotated in Secrets
  Manager. → `modules/data-stores/rds.tf`
- **App secrets:** created with a 90-day rotation policy tag; values written
  out-of-band (`ignore_changes`) so TF never holds them. A DB-URL rotation
  Lambda (to keep `DATABASE_URL` in sync with RDS rotation) is the noted
  follow-up. → `modules/secrets/main.tf`

## No production data in non-prod

- Separate state per env (recommended: separate AWS accounts via the per-env
  roots). Dev uses synthetic data and `force_destroy=true`; staging/prod do not.
  Bedrock/Anthropic configured with no-training agreements. → `terraform/environments/*`

## Data residency / network isolation

- Private subnets for nodes, **intra subnets (no egress)** for control-plane +
  interface endpoints; private EKS API endpoint reached via SSM bastion.
  Borrower data to S3/DynamoDB/Bedrock travels via VPC endpoints, not the
  internet. Default-deny NetworkPolicy on the agent pods. VPC flow logs on.
  → `modules/network`, `modules/eks`, `modules/bastion`, `deploy/chart/.../networkpolicy.yaml`

## Reliability targets

| Target | Control | Where |
| --- | --- | --- |
| RPO 1h | RDS automated backups / PITR (7–14d retention) | `modules/data-stores/rds.tf` |
| RTO 30m | Stateless pods, Multi-AZ spread, PDB, fast reschedule + Karpenter | `deploy/chart`, `modules/karpenter` |
| Idempotent processing | DynamoDB conditional-write idempotency table | `modules/data-stores/dynamodb.tf` |
| 99.9% availability | Multi-AZ RDS, 3-AZ nodes, per-AZ NAT (prod), PDB | `environments/prod/main.tf` |

## Auditability of changes

- All infra change via Terraform (remote state + DynamoDB lock); all cluster
  change via Argo CD from git. Prod gated twice: GitHub Environment approval +
  Argo CD manual sync. CI scans (`tfsec`, ECR scan-on-push, image SBOM/provenance).
