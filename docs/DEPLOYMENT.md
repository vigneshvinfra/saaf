# Deployment — Day-0 Bootstrap

The ordered, end-to-end sequence to stand up an environment from nothing. Each
phase assumes the previous one finished. Most of the stack is automated
(Terraform for AWS, Argo CD for everything in-cluster); the **manual steps are
called out explicitly** and summarised at the bottom.

> This complements `docs/RUNBOOK.md` (which covers the most-likely *incident*,
> not deployment) and `deploy/argocd/README.md` (the Argo object model).

## Prerequisites

- Tools pinned in `.tool-versions`: `terraform 1.12.2`, `kubectl 1.32`,
  `helm 3.16`, plus the `aws` CLI. (Optional: the `argocd` CLI.)
- AWS credentials with enough access to apply the stack (admin for bootstrap).
- A GitHub **read token** for this repo, so Argo CD can pull it (private repo).
- An **ACM certificate** for the agent ingress host
  (`agent.internal.saaffinance.com`) — *not created by Terraform*. Its ARN goes
  into `values-<env>.yaml`. Issue it (DNS-validated) before Phase 4.

---

## Phase 1 — Terraform: remote state (once per AWS account)

```bash
cd terraform/bootstrap
terraform init && terraform apply
```
Creates the S3 state bucket + DynamoDB lock table that every other root uses.
The bucket/table names are already referenced in each env's `backend.tf`.

## Phase 2 — Terraform: per-environment stack

```bash
cd terraform/environments/dev      # then repeat for prod
terraform init && terraform apply
terraform output -json stack        # capture outputs for Phase 4
```
Provisions VPC, EKS, RDS, IAM/KMS, the platform IAM + Karpenter SQS, the
Secrets Manager **containers**, and the bastion. Nothing in-cluster yet.

## Phase 3 — Write the real secret values  *(manual)*

Terraform creates the secrets with `REPLACE_ME` placeholders and then ignores
their value (so it never stores or drifts the real one). Write the real values
out-of-band:

```bash
# DATABASE_URL — build from the RDS endpoint + the RDS-managed master password
aws secretsmanager put-secret-value \
  --secret-id saaf-uw-dev/database-url \
  --secret-string 'postgresql+psycopg://saaf_app:<pw>@<db_endpoint>:5432/saaf'

# ANTHROPIC_API_KEY — dev only (prod uses Bedrock, no key)
aws secretsmanager put-secret-value \
  --secret-id saaf-uw-dev/anthropic-api-key \
  --secret-string 'sk-ant-...'
```

## Phase 4 — Fill placeholders + commit  *(manual)*

Substitute, then commit + push (Argo reads these from git):

- **Repo URL** — replace `https://github.com/<your-org>/saaf-underwriting-infra.git`
  everywhere under `deploy/argocd/` (root, both projects, ApplicationSet,
  `platform/*`) and in `deploy/platform/cluster-resources/values.yaml` (runbook URL).
- **`deploy/argocd/platform/*`** — from `terraform output -json stack`:
  - `<CLUSTER_NAME>` ← `cluster_name`, `<AWS_REGION>` ← `region`
  - `<INTERRUPTION_QUEUE>` ← `karpenter_interruption_queue` (karpenter app)
  - `<KARPENTER_NODE_ROLE>` ← `karpenter_node_role_name` (cluster-resources app)
- **`deploy/chart/.../values-<env>.yaml`**:
  - `secrets.objects[*].arn` ← `database_url_secret_arn` (+ `anthropic_api_key_secret_arn` in dev)
  - `ingress.certificateArn` ← the ACM cert ARN from the prerequisites
- **Pin** each Helm `targetRevision` in `deploy/argocd/platform/*`.

## Phase 5 — Reach the private cluster  *(manual)*

The EKS API is private. Open a shell on the bastion via SSM, then update kubeconfig:

```bash
eval "$(terraform output -json stack | jq -r '.bastion_ssm_command')"   # SSM session
aws eks update-kubeconfig --name saaf-uw-dev --region us-east-1
```

## Phase 6 — Install Argo CD + seed GitOps  *(manual — one script)*

From a context with cluster admin (e.g. the bastion):

```bash
REPO_URL=https://github.com/your-org/saaf-underwriting-infra.git \
GIT_USERNAME=git GIT_TOKEN=<read-token> \
./scripts/bootstrap-argocd.sh
```
The script (`scripts/bootstrap-argocd.sh`) installs Argo CD (pinned chart),
registers the repo, and applies `deploy/argocd/application-root.yaml`. This is
the **only** in-cluster install that isn't itself GitOps-managed (Argo can't
install itself).

## Phase 7 — Argo CD reconciles everything else  *(automatic)*

```
application-root (the one seed)
├── appproject.yaml / project-platform.yaml      (AppProjects)
├── applicationset.yaml      → agent Application per env → agent chart
└── application-platform.yaml (app-of-apps)
    ├── wave 0: aws-load-balancer-controller, karpenter,
    │           secrets-store-csi, kube-prometheus-stack
    └── wave 1: cluster-resources (Karpenter NodePool + agent PrometheusRule)
```
- **dev** auto-syncs; **prod** Applications start `OutOfSync` and wait for a
  manual **Sync** in the Argo UI (the prod gate, paired with the CI image-tag bump).

```bash
kubectl -n argocd get applications -w
```

## Phase 8 — Verify

- `kubectl get pods -A` — controllers (kube-system/monitoring) + agent pods Ready.
- Hit `/healthz` and `/readyz` through the internal ALB (from in-VPC / bastion).
- Confirm the SNS alarm-email subscription (check the inbox for the confirm link).

---

## Ongoing (not Day-0)

- **Image promotion** is GitOps: CI builds + pushes to GHCR and bumps the image
  tag in `values-dev.yaml` (auto on merge) / `values-prod.yaml`
  (`workflow_dispatch`, GitHub Environment approval). Argo then syncs — prod
  manually.

## Manual-step summary

| # | Manual step | Phase | Automated alternative? |
|---|---|---|---|
| 1 | `terraform apply` bootstrap + env stacks | 1–2 | IaC entry point (expected) |
| 2 | Write real secret values (`put-secret-value`) | 3 | Could add a rotation Lambda (out of scope) |
| 3 | Fill placeholders + ACM cert ARN, commit | 4 | — (edit, then GitOps) |
| 4 | SSM to bastion + `update-kubeconfig` | 5 | — (private API by design) |
| 5 | `./scripts/bootstrap-argocd.sh` (install Argo + register repo + seed) | 6 | The script *is* the automation |

Everything not in this table — all platform controllers, the NodePool, the
PrometheusRule, the agent, EKS managed addons — is installed automatically by
Argo CD or Terraform.
