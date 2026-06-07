# CLAUDE.md — working notes for this repo

Infrastructure to **deploy and operate** the Saaf underwriting-assist agent on
EKS. The agent (`src/agent/`) is the ML team's reference service, **vendored
unchanged** — do not modify it; deploy and operate it.

## Golden rules
- **Don't change the agent.** It's a synchronous FastAPI service
  (`POST /v1/items/process`, `/healthz`, `/readyz`). Infra wraps it.
- **No queue / no KEDA.** The entry point is an internal ALB; scaling is CPU HPA
  + Karpenter. SQS+KEDA was deliberately removed (would need a consumer = new app
  code). It's a *documented future evolution*, not a TODO. See `docs/DESIGN.md`.
- **Terraform is pure AWS.** All Helm/Kubernetes delivery is via Argo CD, so the
  TF needs only the `aws` (+ `http`) provider — keep it that way (validates with
  no cluster).
- **EKS Pod Identity, not IRSA.** New workload identities = an IAM role
  (`pods.eks.amazonaws.com`) + `aws_eks_pod_identity_association`. Scope policies
  to exact ARNs; no `*` resources.

## Layout
- `terraform/bootstrap` — remote state (apply once). `terraform/global` — ECR +
  GitHub OIDC. `terraform/modules/stack` — composes everything; env roots
  (`environments/{dev,staging,prod}`) just call it with per-env sizing.
- `deploy/chart/underwriting-agent` — Helm chart (+ `values-<env>.yaml`).
- `deploy/argocd` — AppProject + ApplicationSet + root app. `deploy/platform` —
  Karpenter NodePool + PrometheusRule (GitOps).
- `docs/` — DESIGN (1-page), RUNBOOK, COST, COMPLIANCE, AI-USAGE, architecture.

## Validate before claiming done
```bash
make tf-fmt && ./scripts/tf-validate-all.sh        # all roots, no AWS needed
helm lint deploy/chart/underwriting-agent -f deploy/chart/underwriting-agent/values-prod.yaml
make test                                           # pytest
```
- `terraform validate` uses `init -backend=false` (offline). Module changes that
  pull upstream modules need network to download them once.
- `for_each` must key on values **known at plan time** — index, not IDs created
  in the same apply.

## Conventions
- Name prefix `saaf-uw-<env>`. Tag everything (Project/Environment/ManagedBy).
- KMS on every store; TLS-only bucket policies; audit bucket is WORM (Object
  Lock) — never `force_destroy` it.
- Chart resource name is fixed (`underwriting-agent`) via `agent.name`; the SA
  name must match the Pod Identity association in `modules/agent-identity`.
- Prod changes are double-gated: GitHub Environment approval + Argo CD manual sync.

## Models
When wiring LLM config: prod uses **Bedrock** (`anthropic.claude-sonnet-4-6-v1:0`)
via PrivateLink; dev/staging use the **Anthropic API** key from Secrets Manager.
