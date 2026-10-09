#!/usr/bin/env bash
# Spins up the whole crossplane-experiments demo from scratch:
#   1. creates the kind cluster (kind-config.yaml, name "cnpg-crossplane")
#   2. (re)packages the self-authored WordPress chart (scripts/build-charts.sh)
#   3. refreshes the umbrella chart's Helm dependencies (chart/charts/*.tgz)
#   4. helm install/upgrade --install's the umbrella chart
#
# Usage: ./scripts/deploy.sh [--hostname <vm-ip-or-dns-name>] [extra helm args...]
#   --hostname NAME  sets Helm value reverseProxy.hostname (also settable via
#                    the VM_HOSTNAME env var; the flag wins). Default: this VM's
#                    own hostname (`hostname -f`).
#
# Safe to re-run: if the kind cluster "cnpg-crossplane" already exists it
# is reused as-is (use scripts/destroy.sh first for a truly clean slate),
# and the Helm release is installed if absent or upgraded if present.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

CLUSTER_NAME="cnpg-crossplane"
RELEASE_NAME="crossplane-experiments"
NAMESPACE="crossplane-system"
KIND_MEMORY_LIMIT="7g"
KIND_CPU_LIMIT="3"
VM_HOSTNAME="${VM_HOSTNAME:-$(hostname -f 2>/dev/null || hostname)}"

HELM_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hostname)
      [[ $# -ge 2 ]] || { echo "--hostname requires a value" >&2; exit 1; }
      VM_HOSTNAME="$2"; shift 2 ;;
    --hostname=*) VM_HOSTNAME="${1#*=}"; shift ;;
    *) HELM_ARGS+=("$1"); shift ;;
  esac
done
HELM_ARGS+=(--set "reverseProxy.hostname=${VM_HOSTNAME}")

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "==> kind cluster '${CLUSTER_NAME}' already exists, reusing it"
else
  echo "==> Creating kind cluster '${CLUSTER_NAME}'..."
  kind create cluster --config kind-config.yaml
fi

echo "==> Applying kind node limits (${KIND_MEMORY_LIMIT} RAM, ${KIND_CPU_LIMIT} CPUs)..."
while IFS= read -r NODE_NAME; do
  [[ -n "${NODE_NAME}" ]] || continue
  docker update --memory "${KIND_MEMORY_LIMIT}" --memory-swap "${KIND_MEMORY_LIMIT}" --cpus "${KIND_CPU_LIMIT}" "${NODE_NAME}" >/dev/null
done < <(kind get nodes --name "${CLUSTER_NAME}")

echo "==> Packaging the self-authored WordPress chart..."
./scripts/build-charts.sh

# `helm dependency build` resolves each chart/Chart.yaml dependency's
# `repository` URL against the LOCAL repo cache (~/.config/helm/repositories.yaml)
# -- it does NOT fetch straight from an inline URL the way `helm install
# some/chart --repo <url>` does, so every non-OCI repository referenced
# there must already be registered via `helm repo add` first, or this
# fails with "no repository definition for ...". Idempotent: `helm repo
# add` no-ops (with a warning) if the name+URL already match.
echo "==> Ensuring Helm dependency repos are registered..."
helm repo add crossplane-stable https://charts.crossplane.io/stable >/dev/null
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null
helm repo add cnpg https://cloudnative-pg.github.io/charts >/dev/null
helm repo add cloudnative-pg https://cloudnative-pg.github.io/charts >/dev/null
helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null
helm repo add external-secrets https://charts.external-secrets.io >/dev/null
helm repo update crossplane-stable metrics-server cnpg cloudnative-pg hashicorp external-secrets >/dev/null

echo "==> Refreshing umbrella chart's Helm dependencies..."
helm dependency build chart/

echo "==> Installing/upgrading Helm release '${RELEASE_NAME}' in namespace '${NAMESPACE}'..."
helm upgrade --install "${RELEASE_NAME}" chart/ \
  --namespace "${NAMESPACE}" --create-namespace \
  --timeout 10m ${HELM_ARGS[@]+"${HELM_ARGS[@]}"}

echo "==> Running Helm end-to-end test for '${RELEASE_NAME}'..."
helm test "${RELEASE_NAME}" --namespace "${NAMESPACE}" --logs --timeout 5m

cat <<'EOF'

==> Done. The demo should reconcile within a couple of minutes.
    See the "helm install"/"helm upgrade" NOTES above for URLs, or:
      kubectl get appenvironment -A
      kubectl get managed
    for status. Add "127.0.0.1 crossplane-experiment" to /etc/hosts
    (or just use https://localhost:9443) to browse the demo.
EOF
