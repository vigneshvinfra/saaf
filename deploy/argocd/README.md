# GitOps delivery (Argo CD)

The agent is delivered to EKS by **Argo CD**, not by `helm upgrade` in CI. CI's
job ends at "a tested image exists in GHCR and the desired tag is committed to
git"; Argo CD reconciles the cluster to git.

## The objects

| File | Kind | Role |
| --- | --- | --- |
| `appproject.yaml` | `AppProject` | Security boundary for the agent — namespaced-only, locks down source repo, allowed namespaces, and the resource kinds the agent may create. |
| `applicationset.yaml` | `ApplicationSet` | Fans out one agent `Application` per env (dev/prod) from one definition. |
| `project-platform.yaml` | `AppProject` | Privileged boundary for cluster platform controllers + CRDs (cluster-scoped resources allowed, scoped to `kube-system`/`monitoring` and trusted chart repos). |
| `application-platform.yaml` | `Application` | App-of-apps for the platform layer; manages the child Applications under `platform/`. |
| `platform/*.yaml` | `Application` | One per controller the agent depends on: AWS Load Balancer Controller, Karpenter, Secrets Store CSI (+ AWS provider), kube-prometheus-stack. Helm values are substituted from `terraform output`. |
| `application-root.yaml` | `Application` | App-of-apps you bootstrap by hand once; it then manages every file above from git. |

The platform controllers are what the agent's own manifests assume already exist — the ALB (Ingress), the Secrets Store CSI mount (SecretProviderClass), and the ServiceMonitor/PrometheusRule CRDs. EKS-managed addons (CoreDNS, kube-proxy, VPC CNI, pod-identity-agent, metrics-server, EBS CSI) come from Terraform, not here.

## Flow

```
git push (chart or values-<env>.yaml change)
      │
      ▼
Argo CD detects drift ──▶ dev:     auto-sync + self-heal
                         prod:     OutOfSync → human clicks Sync  (the prod gate)
```

Image promotion is GitOps too: CI builds `:<git-sha>`, pushes to GHCR, and opens
a commit/PR bumping `image.tag` in `values-<env>.yaml`. Merging to dev
auto-deploys; prod waits for a manual Sync by `saaf:platform-oncall`.

## Bootstrap (once per cluster, from the SSM bastion)

```bash
# 1. Install Argo CD itself (out-of-band — it's what runs everything below):
#      helm install argo-cd argo/argo-cd -n argocd --create-namespace
# 2. Apply the one root app; it then pulls everything else from git:
kubectl apply -n argocd -f deploy/argocd/application-root.yaml
```

The root app then creates both projects, the agent `ApplicationSet`, and the
platform app-of-apps — which installs the controllers. After that, never
`kubectl apply` these again — change them in git.

## Before first use

- Replace `https://github.com/<your-org>/saaf-underwriting-infra.git` with the
  real repo URL across all the files here (root, both projects, the
  ApplicationSet, and `platform/*`), and tie `saaf:platform-oncall` in
  `appproject.yaml` to your SSO group.
- Fill the placeholders in `platform/*.yaml` from `terraform output` and pin each
  chart `targetRevision`:
  - `<CLUSTER_NAME>` / `<AWS_REGION>` (`cluster_name`, `region`)
  - `<INTERRUPTION_QUEUE>` (`karpenter_interruption_queue`) — Karpenter
  - `<KARPENTER_NODE_ROLE>` (`karpenter_node_role_name`) — cluster-resources
- The Karpenter `NodePool`/`EC2NodeClass` and the agent `PrometheusRule` are
  delivered by the `cluster-resources` app (sync-wave 1) from the
  `deploy/platform/cluster-resources` Helm chart — no manual `${...}` substitution.
