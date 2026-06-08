# Saaf — Underwriting-Assist Agent: Production Infrastructure

Infrastructure for running Saaf Finance's **underwriting-assist agent** in
production on **AWS EKS**. The agent itself (`src/agent/`) is the reference
service shipped by the ML team and is vendored here **unchanged** — this repo is
about *deploying and operating* it safely in a regulated (financial-services)
environment.

> This is a take-home build. It is designed to be **statically valid and
> secure** (`terraform validate` + `tfsec` clean, `pytest` green; the agent ships
> via the Helm chart, rendered and linted in CI for every environment).
> It is **not** intended to `apply` against a real AWS account — that is out of
> scope per the brief. Reasoning lives in [`docs/`](docs/).

## TL;DR architecture

```
loan-officer system (in-VPC)
        │  HTTPS POST /v1/items/process
        ▼
  internal ALB (TLS 1.2+)  ──▶  Service  ──▶  agent pods (EKS)        ┌─ RDS Postgres (loan/item state)
        ▲                                     scaled by CPU HPA       ├─ S3 (borrower docs, KMS)
   /healthz /readyz                           Pod Identity (least-priv)├─ S3 audit (Object Lock, 7yr)
                                                     │  ───────────────┤  DynamoDB (idempotency keys)
                                                     └────────────────▶├─ Bedrock via PrivateLink (prod)
                                                                       └─ SES (borrower email)

Synchronous request/response — the agent's native contract. We deploy and
operate it as shipped; we do not put a queue in front (that would require
building a consumer). SQS + queue-depth autoscaling is documented as the
future evolution if arrival outgrows synchronous serving — see docs/DESIGN.md.
```

Full diagram + reasoning: [`docs/architecture.md`](docs/architecture.md),
[`docs/DESIGN.md`](docs/DESIGN.md).

## Repository layout

```
.
├── src/agent/                 # Reference agent (vendored, unchanged)
├── tests/                     # Smoke test (CI gate)
├── Dockerfile, pyproject.toml # Vendored build
├── terraform/
│   ├── bootstrap/             # Remote state (S3 + DynamoDB lock) — apply once
│   ├── modules/               # Reusable, composable modules
│   │   ├── network/           #   VPC, subnets, NAT, VPC endpoints (Bedrock/S3/...)
│   │   ├── eks/               #   Cluster, Pod Identity, KMS logs, system nodes
│   │   ├── karpenter/         #   Just-in-time nodes for burst headroom
│   │   ├── platform-addons/   #   LB Controller, EBS CSI, Secrets Store CSI
│   │   ├── data-stores/       #   RDS, S3 docs, S3 audit (Object Lock), DynamoDB
│   │   ├── secrets/           #   Secrets Manager + rotation
│   │   ├── agent-identity/    #   Least-priv Pod Identity role for the agent SA
│   │   ├── observability/     #   CloudWatch dashboards + alarms + SNS
│   │   └── bastion/           #   SSM-only bastion for the private API endpoint
│   └── environments/          # dev / prod roots (separate state)
├── deploy/
│   └── chart/underwriting-agent/  # Helm chart for the agent
├── .github/workflows/         # ci.yml (lint/test/build/validate/scan) + cd.yml (build+push GHCR, promote)
└── docs/                      # DEPLOYMENT, DESIGN, RUNBOOK, COST, COMPLIANCE, AI-USAGE, diagrams
```

## Quick start

### Run the agent locally (no credentials — mock LLM)
```bash
make install run-local
# in another shell:
curl -s localhost:8080/healthz
curl -s -XPOST localhost:8080/v1/items/process \
  -H 'content-type: application/json' -d @examples/sample_loan.json | jq
```

### Validate / scan the Terraform (no AWS account needed)
```bash
make tf-fmt tf-validate tf-security
```

### Plan an environment (requires AWS creds + bootstrapped state)
```bash
cd terraform/bootstrap && terraform init && terraform apply   # once per account
make tf-plan ENV=dev
```

### Deploy end to end
The full Day-0 bootstrap order (Terraform → secrets → Argo CD → app), with every
manual step called out, is in **[`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md)**.
Argo CD install + repo registration + root-app seed is scripted in
[`scripts/bootstrap-argocd.sh`](scripts/bootstrap-argocd.sh).

## What maps to the spec

| Spec requirement | Where it lives |
| --- | --- |
| KMS at rest (all stores) | `modules/data-stores`, `modules/eks`, `bootstrap` |
| TLS 1.2+ in transit | ALB listener policy (`deploy/chart`), VPC endpoints |
| 7-year auditable LLM trail | `modules/data-stores` audit bucket (Object Lock + lifecycle) |
| Least-privilege IAM | `modules/agent-identity` (Pod Identity, scoped) |
| Secret rotation (quarterly) | `modules/secrets` (rotation schedule + `ignore_changes`) |
| No prod data in non-prod | separate accounts/state per env; synthetic dev data |
| Idempotent processing | DynamoDB idempotency table (`modules/data-stores`) the agent's store layer keys on |
| RPO 1h / RTO 30m | RDS PITR + multi-AZ; stateless pods, fast reschedule |
| Bursty scale-out | CPU HPA headroom + Karpenter just-in-time nodes |
| ≤ $1.50/item @ p50 | [`docs/COST.md`](docs/COST.md) |

See [`docs/COMPLIANCE.md`](docs/COMPLIANCE.md) for the full control mapping.
