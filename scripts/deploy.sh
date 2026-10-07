#!/usr/bin/env bash
# Spins up the whole crossplane-experiments demo from scratch:
#   1. creates the kind cluster (kind-config.yaml, name "cnpg-crossplane")
#   2. (re)packages the self-authored WordPress chart (scripts/build-charts.sh)
#   3. refreshes the umbrella chart's Helm dependencies (chart/charts/*.tgz)
#   4. helm install/upgrade --install's the umbrella chart
#
# Usage: ./scripts/deploy.sh
#
# Safe to re-run: if the kind cluster "cnpg-crossplane" already exists it
# is reused as-is (use scripts/destroy.sh first for a truly clean slate),
# and the Helm release is installed if absent or upgraded if present.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

CLUSTER_NAME="cnpg-crossplane"
RELEASE_NAME="crossplane-experiments"
NAMESPACE="crossplane-system"

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "==> kind cluster '${CLUSTER_NAME}' already exists, reusing it"
else
  echo "==> Creating kind cluster '${CLUSTER_NAME}'..."
  kind create cluster --config kind-config.yaml
fi

echo "==> Packaging the self-authored WordPress chart..."
./scripts/build-charts.sh

echo "==> Refreshing umbrella chart's Helm dependencies..."
helm dependency build chart/

echo "==> Installing/upgrading Helm release '${RELEASE_NAME}' in namespace '${NAMESPACE}'..."
helm upgrade --install "${RELEASE_NAME}" chart/ \
  --namespace "${NAMESPACE}" --create-namespace \
  --timeout 10m "$@"

cat <<'EOF'

==> Done. The demo should reconcile within a couple of minutes.
    See the "helm install"/"helm upgrade" NOTES above for URLs, or:
      kubectl get appenvironment -A
      kubectl get managed
    for status. Add "127.0.0.1 crossplane-experiment" to /etc/hosts
    (or just use https://localhost:9443) to browse the demo.
EOF
