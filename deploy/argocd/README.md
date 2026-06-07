# GitOps delivery (Argo CD)

The agent is delivered to EKS by **Argo CD**, not by `helm upgrade` in CI. CI's
job ends at "a tested image exists in ECR and the desired tag is committed to
git"; Argo CD reconciles the cluster to git.

## The three objects

| File | Kind | Role |
| --- | --- | --- |
| `appproject.yaml` | `AppProject` | Security boundary — locks down source repo, allowed destination namespaces, and the resource kinds the agent may create. |
| `applicationset.yaml` | `ApplicationSet` | Fans out one `Application` per env (dev/staging/prod) from one definition. |
| `application-root.yaml` | `Application` | App-of-apps you bootstrap by hand once; it then manages the two files above from git. |

## Flow

```
git push (chart or values-<env>.yaml change)
      │
      ▼
Argo CD detects drift ──▶ dev:     auto-sync + self-heal
                         staging:  auto-sync + self-heal
                         prod:     OutOfSync → human clicks Sync  (the prod gate)
```

Image promotion is GitOps too: CI builds `:<git-sha>`, pushes to ECR, and opens
a commit/PR bumping `image.tag` in `values-<env>.yaml`. Merging to dev/staging
auto-deploys; prod waits for a manual Sync by `saaf:platform-oncall`.

## Bootstrap (once per cluster, from the SSM bastion)

```bash
# Argo CD itself is installed by the platform layer. Then:
kubectl apply -n argocd -f deploy/argocd/application-root.yaml
```

After that, never `kubectl apply` these again — change them in git.

## Before first use

Replace `https://github.com/<your-org>/saaf-underwriting-infra.git` in all three
files with the real repo URL, and tie the `saaf:platform-oncall` group in
`appproject.yaml` to your SSO group.
