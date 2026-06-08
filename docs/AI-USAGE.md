# AI usage

This build was done with **Claude Code** (Anthropic) as the primary authoring
tool, used the way the brief encourages — to draft, then critically adapt. This
note records *how* it was used and, more importantly, where its suggestions were
**overridden**, since "adapt AI suggestions" is part of what's being assessed.

## How it was used
- **Repo + spec ingestion:** read the service spec PDF and the skeleton agent
  repo, extracted the runtime contract (endpoints, env config, store/LLM
  interfaces) and the compliance/SLO requirements.
- **Used my prior experience & judgement:** pointed it at my existing `~/TF` EKS setup and asked
  it to lift the proven patterns (EKS module 20.x, **EKS Pod Identity**,
  KMS-encrypted control-plane logs, private endpoint + SSM bastion, Secrets Store
  CSI, gp3) into a properly modular layout.
- **Module + manifest authoring:** generated the Terraform modules, the Helm
  chart, the Argo CD manifests (app + platform projects), the CI/CD workflows,
  the Day-0 bootstrap guide (`docs/DEPLOYMENT.md` + `scripts/bootstrap-argocd.sh`),
  and these docs — each validated as it went (`terraform validate`,
  `helm lint/template`, `yq`).

## Where I corrected / overrode the AI (the important part)
1. **Removed a speculative SQS + KEDA design.** The AI's first cut (and my own
   initial instinct) added an SQS ingestion queue with KEDA queue-depth
   autoscaling — a clean fit for the bursty pattern *on paper*. On review it was
   wrong for this brief: the agent is a **synchronous HTTP service**, so a queue
   needs a **consumer we'd have to build**, and the brief says *deploy/operate,
   don't change the agent.* I had it rip out KEDA/SQS and standardise on
   ALB + CPU HPA, documenting SQS as a *future evolution*. (This is visible in
   the commit trail.)
2. **Caught a half-wired data flow.** Before the removal, the chart had an ALB
   *and* a KEDA `ScaledObject` pointing at a non-existent queue/consumer — two
   entry points, no working async path. Tracing the request flow surfaced the
   incoherence and drove decision (1).
3. **Simplified the Helm `_helpers.tpl`.** Rejected the boilerplate
   `name`/`fullname`/override gymnastics (dead code given a fixed release name)
   and the full "recommended labels" set, in favour of a minimal, readable
   helper.
4. **Fixed plan-time-unknown `for_each`.** Keyed `for_each` by index rather than
   by resource IDs created in the same apply (node SG, subnets), and made VPC
   interface endpoints AZ-aware so they only land in AZs that offer the service.
5. **Resolved the DATABASE_URL ↔ RDS rotation tension** honestly — RDS-managed
   auto-rotating master secret + a documented follow-up Lambda, rather than
   pretending static creds rotate.
6. **Cut speculative scope: dropped `terraform/global` and the `staging`
   environment.** The AI's layout carried a `global` root and a third env that
   added structure without earning it for this brief. I collapsed to
   `bootstrap` + `dev`/`prod` — the minimum that still demonstrates per-env
   sizing — same "don't ship complexity the spec didn't ask for" call as (1).
7. **Made platform resources first-class GitOps.** Repackaged the loose Karpenter
   NodePool + PrometheusRule manifests as an Argo-managed Helm chart
   (`deploy/platform/cluster-resources`), so *everything* in-cluster flows through
   Argo CD rather than a mix of `kubectl apply` and GitOps.

## What I verified myself (not taken on trust)
- `terraform fmt -check` + `validate` across bootstrap and both envs
  (`dev`/`prod`) — green.
- `helm lint` + `helm template` for the agent chart (`dev`/`prod`) and the
  platform `cluster-resources` chart — green.
- `pytest` smoke suite (boots the app, exercises the mock agent path) — green.
- Built the agent image (`docker build`) — green.

## Prompting style
Short, iterative, review-heavy: generate one coherent slice → read it →
challenge it ("where is the queue in the request flow?", "why do we have KEDA?")
→ adjust. The most valuable prompts were the *skeptical* ones that forced the
design back to what the spec actually asked for.
