#!/usr/bin/env bash
# Packages charts/wordpress/ (our self-authored, non-Bitnami WordPress
# chart) into chart/files/ and generates a classic Helm chart repo
# index.yaml alongside it, so the umbrella chart (chart/) can embed both
# and serve them via a plain nginx static file server (the in-cluster
# chart "registry"). Note: we deliberately use a classic HTTP chart repo
# instead of an OCI registry here - provider-helm's OCI client creates its
# registry.Client with no TLS options at all, ignoring
# insecureSkipTLSVerify for the manifest-resolution step (confirmed
# upstream bug as of provider-helm v1.4.0), so OCI+self-signed-TLS doesn't
# work reliably. The classic repo protocol has no such issue.
#
# Run this whenever charts/wordpress/ changes, then re-run
# `helm dependency update chart/` + `helm upgrade --install`.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

rm -f chart/files/wordpress-*.tgz chart/files/index.yaml
mkdir -p chart/files
helm package charts/wordpress -d chart/files/
helm repo index chart/files
echo "Packaged $(ls chart/files/wordpress-*.tgz) and chart/files/index.yaml"
