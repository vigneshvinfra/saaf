#!/usr/bin/env bash
# Validate every Terraform environment + the bootstrap config without
# touching a real backend or AWS account. Used by `make tf-validate` and CI.
# `terraform validate` needs an initialized working dir but NOT credentials,
# so we init with -backend=false.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0

targets=(
  terraform/bootstrap
  terraform/environments/dev
  terraform/environments/prod
)

echo "==> terraform fmt -check -recursive"
terraform fmt -check -recursive terraform || { echo "fmt drift — run 'make tf-fmt'"; fail=1; }

for t in "${targets[@]}"; do
  echo "==> validating $t"
  ( cd "$t" && terraform init -backend=false -input=false >/dev/null && terraform validate ) \
    || { echo "validate failed: $t"; fail=1; }
done

exit $fail
