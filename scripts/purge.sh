#!/usr/bin/env bash
# Removes everything deploy.sh downloads or generates locally:
#   - Helm repos registered by deploy.sh
#   - dependency tarballs in chart/charts/ (helm dependency build)
#   - the packaged WordPress chart tarball(s) + index.yaml in chart/files/
#   - the Helm repository cache of the removed repos
# Does NOT touch the kind cluster (see destroy.sh). Re-run deploy.sh to
# regenerate everything.
#
# Usage: ./scripts/purge.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

HELM_REPOS=(crossplane-stable cloudnative-pg hashicorp external-secrets)

if command -v helm >/dev/null 2>&1; then
  echo "==> Removing Helm repos..."
  registered="$(helm repo list -o json 2>/dev/null | tr ',' '\n' | sed -n 's/.*"name":"\([^"]*\)".*/\1/p' || true)"
  for repo in "${HELM_REPOS[@]}"; do
    if grep -qx "$repo" <<<"$registered"; then
      helm repo remove "$repo" >/dev/null && echo "    removed $repo"
    fi
  done
fi

echo "==> Removing downloaded/generated chart tarballs..."
rm -fv chart/charts/*.tgz
rm -fv chart/files/wordpress-*.tgz chart/files/index.yaml

echo "==> Done. Run ./scripts/deploy.sh to regenerate."
