#!/usr/bin/env bash
# This is the one piece that can't be GitOps-managed (Argo can't install itself)
# Run it ONCE per cluster, from a machine with kube admin on the target cluster (e.g. the SSM bastion).
#
# It:
#   1. installs Argo CD via its Helm chart (pinned version)
#   2. registers this git repo as an Argo repository (for private repos)
#   3. applies deploy/argocd/application-root.yaml — the app-of-apps seed
# After this, everything else reconciles from git. See docs/DEPLOYMENT.md.
#
# Usage:
#   REPO_URL=https://github.com/your-org/saaf-underwriting-infra.git \
#   GIT_USERNAME=git GIT_TOKEN=ghp_xxx \
#   ./scripts/bootstrap-argocd.sh
set -euo pipefail

# ----- config (override via env) -------------------------------------------
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
# Pin the argo-cd HELM CHART version (not the app version). Bump deliberately.
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-7.6.12}"
REPO_URL="${REPO_URL:-https://github.com/<your-org>/saaf-underwriting-infra.git}"
GIT_USERNAME="${GIT_USERNAME:-}"   # PAT username (often 'git' or your handle)
GIT_TOKEN="${GIT_TOKEN:-}"         # PAT/deploy token with read on the repo
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_APP="${ROOT_APP:-$ROOT_DIR/deploy/argocd/application-root.yaml}"

echo "==> Installing Argo CD (chart $ARGOCD_CHART_VERSION) into ns/$ARGOCD_NAMESPACE"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
# Defaults are sane for a first install. For production, add a values file with
# HA (controller/replica counts), TLS, and SSO/RBAC for the `saaf:platform-oncall`
# group referenced in deploy/argocd/appproject.yaml.
helm upgrade --install argo-cd argo/argo-cd \
  --namespace "$ARGOCD_NAMESPACE" --create-namespace \
  --version "$ARGOCD_CHART_VERSION" \
  --wait

echo "==> Registering the git repo with Argo CD"
if [[ -n "$GIT_TOKEN" ]]; then
  # Declarative repo registration via a labelled Secret (no argocd CLI needed).
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: repo-saaf-underwriting-infra
  namespace: $ARGOCD_NAMESPACE
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: $REPO_URL
  username: $GIT_USERNAME
  password: $GIT_TOKEN
EOF
else
  echo "    GIT_TOKEN not set — skipping repo registration."
  echo "    (Fine for a PUBLIC repo; required for a private one.)"
fi

echo "==> Applying the root app-of-apps: $ROOT_APP"
kubectl apply -n "$ARGOCD_NAMESPACE" -f "$ROOT_APP"

cat <<EOF

Done. Argo CD will now reconcile the rest from git:
  root -> AppProjects + agent ApplicationSet + platform app-of-apps
       -> controllers (wave 0) -> cluster-resources (wave 1) -> agent

Watch progress:
  kubectl -n $ARGOCD_NAMESPACE get applications -w

Initial admin password:
  kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret \\
    -o jsonpath='{.data.password}' | base64 -d; echo
EOF
