# Design — Underwriting-Assist Agent Infrastructure

**Scope.** Deploy and operate the ML team's agent (vendored unchanged) on EKS,
in a regulated financial-services posture. A narrow, well-architected slice:
network → cluster → data → identity → delivery → observability. Not a real
`apply`; the bar is *statically valid + secure* (CI is green, `tfsec` clean).

## Key decisions & trade-offs

**Synchronous, not queue-based.** The agent ships as a synchronous HTTP service
(`POST /v1/items/process`). A queue (SQS) + queue-depth autoscaling (KEDA) is a
tempting fit for the bursty arrival pattern — but it requires *building a
consumer* that turns queue messages into HTTP calls, which is new application
code. The brief is explicit: *deploy and operate it, don't change it.* So the
entry point is an internal ALB and the service scales on CPU via HPA, with
Karpenter adding nodes for burst headroom. At the stated load (250 items/hr peak,
12-month target) synchronous serving is comfortable. **Evolution, not now:** if
arrival outgrows sync, front it with SQS + a queue-depth scaler. Documenting this
as deferred is the deliberate call — I removed an earlier KEDA/SQS draft once it
became clear it was speculative complexity the spec didn't ask for.

**EKS over Lambda/Fargate.** The agent is a long-lived uvicorn server with a
pooled Postgres connection; EKS gives one platform for the agent + Karpenter +
observability + GitOps, and matches the org's existing Kubernetes footprint.
Trade-off: more platform to own than Lambda. Mitigated by managed add-ons +
Karpenter + Argo CD.

**EKS Pod Identity, not IRSA.** Every workload identity (agent, LB controller,
EBS CSI, Karpenter) uses Pod Identity associations — no OIDC annotations, simpler
rotation, least-privilege per ServiceAccount. The agent role is scoped to exact
ARNs (read docs, append-only audit, idempotency table, its own secrets, one
Bedrock model, send-as one SES address) — no `*` resources.

**Bedrock (prod) / Anthropic API (dev).** Prod calls Bedrock over a
PrivateLink endpoint: no internet egress for borrower data, IAM-auditable, no
API key to rotate, no-training by default. Non-prod uses the Anthropic API (key
in Secrets Manager) so the secret-rotation + egress path is also exercised.

**GitOps delivery (Argo CD).** CI builds a tested, scanned image (`:<git-sha>`,
pushed to GHCR with the built-in `GITHUB_TOKEN` — no static AWS keys) and commits the tag into
`values-<env>.yaml`. Argo CD reconciles: dev auto-syncs, **prod is a
manual sync gated by a GitHub Environment approval** — two independent gates on
prod change.

## Compliance posture (financial services)

KMS at rest on every store (RDS, both S3 buckets, DynamoDB, secrets, EKS secrets,
control-plane logs); TLS 1.2+ in transit (ALB policy + VPC endpoints + bucket
deny-non-TLS). The **7-year LLM-call audit trail** lands in an S3 bucket with
**Object Lock in COMPLIANCE mode** — immutable for 7 years, not even root can
delete it — tiered to Glacier to control cost. Least-privilege IAM throughout.
Secret rotation: RDS master is auto-rotated by RDS; app secrets carry a 90-day
rotation policy. No prod data in non-prod (separate accounts/state, synthetic dev
data). Full mapping: [`COMPLIANCE.md`](COMPLIANCE.md).

## Reliability

Stateless pods (RTO 30m via fast reschedule + PDB + multi-AZ spread); RDS
Multi-AZ + PITR (RPO 1h easily met). **Idempotency** — the spec's "no duplicate
emails/tasks" — is backed by a DynamoDB table the agent's store layer keys each
(loan_id,item_id) write on with a conditional put. We provide the resource;
enabling it is a one-line change in the agent's store, out of our scope to edit.

## Cost

Modelled at **≈$0.30–0.50/item** against the $1.50 target, dominated by the LLM
call, not compute. Spot for non-prod + Karpenter consolidation keep idle cost
low. Details + sensitivity: [`COST.md`](COST.md).

## What I'd do next (called out honestly)

DB-credential rotation Lambda to keep `DATABASE_URL` in sync with RDS rotation;
WAF + authn on the ALB; cross-region audit replication; SQS+KEDA if load grows;
OTel collector → managed Prometheus/Grafana wiring finished end-to-end.
