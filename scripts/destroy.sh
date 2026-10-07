#!/usr/bin/env bash
# Tears down the crossplane-experiments demo by deleting the kind cluster
# "cnpg-crossplane" entirely (the cluster is the only stateful part of
# this demo - Vault runs in dev-mode/in-memory and everything else is
# reconciled fresh on the next ./scripts/deploy.sh run).
#
# Usage: ./scripts/destroy.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

CLUSTER_NAME="cnpg-crossplane"

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "==> Deleting kind cluster '${CLUSTER_NAME}'..."
  kind delete cluster --name "${CLUSTER_NAME}"
  echo "==> Done. Run ./scripts/deploy.sh to recreate the demo."
else
  echo "==> kind cluster '${CLUSTER_NAME}' does not exist, nothing to do."
fi
