# crossplane-experiments

A single Helm "umbrella" chart that stands up a complete demo of a
Crossplane Composition provisioning **WordPress + Keycloak + MariaDB
(for WordPress) + PostgreSQL (for Keycloak)**, with WordPress
authenticating exclusively against Keycloak's `setup` realm via OIDC.

No Bitnami images/charts are used anywhere. Every component is either
an official upstream chart/image or self-authored:

| Component          | Source                                                    |
|---------------------|------------------------------------------------------------|
| Crossplane          | `https://charts.crossplane.io/stable` (official)           |
| CloudNativePG       | `https://cloudnative-pg.github.io/charts` (official)        |
| mariadb-operator    | `oci://ghcr.io/mariadb-operator/charts` (official)          |
| Keycloak            | `codecentric/keycloakx` chart, `quay.io/keycloak/keycloak` image |
| WordPress           | self-authored chart (`charts/wordpress/`), official `wordpress` image |
| Chart registry      | plain `nginx:1.27-alpine` serving a classic Helm chart repo |
| Reverse proxy        | plain `nginx:1.27-alpine`, self-signed TLS                  |

## One-command install

```bash
# 1. Create the kind cluster (includes the port mapping used by the
#    reverse-proxy URL below).
kind create cluster --config kind-config.yaml

# 2. Install everything: Crossplane, CloudNativePG, mariadb-operator,
#    providers, the XRD/Composition, the in-cluster chart registry, the
#    reverse proxy, and (by default) a demo claim instantiating the
#    full WordPress+Keycloak+MariaDB+Postgres stack.
helm install crossplane-experiments chart/ -n crossplane-system --create-namespace
```

That's it — within a couple of minutes the whole stack (Crossplane,
operators, Keycloak, its Postgres, WordPress, its MariaDB, the OIDC
Realm/User/Client wiring) reconciles automatically. Re-run
`helm upgrade crossplane-experiments chart/ -n crossplane-system` any
time you change something.

If you change the self-authored WordPress chart under `charts/wordpress/`,
regenerate the embedded package/index first:

```bash
./scripts/build-charts.sh
```

## Checking it's working

```bash
kubectl get release.helm.crossplane.io -n default
kubectl get realm.realm.keycloak.crossplane.io,user.user.keycloak.crossplane.io,client.openidclient.keycloak.crossplane.io
kubectl get pods -n default
```

### Single external URL

The chart also deploys a small nginx reverse proxy (self-signed TLS)
exposing both apps under one address:

- `https://crossplane-experiment:9443/wordpress`
- `https://crossplane-experiment:9443/keycloak`

To reach it from your host:

1. Add a hosts entry (or just use `localhost`):
   ```
   echo "127.0.0.1 crossplane-experiment" | sudo tee -a /etc/hosts
   ```
2. Make sure the kind cluster was created with `kind-config.yaml`
   (maps host port `9443` -> the reverse proxy's NodePort `30443`).
3. Browse to `https://crossplane-experiment:9443/wordpress` or
   `/keycloak` (accept the self-signed certificate warning).

> Note: WordPress and Keycloak both use their internal Service DNS
> names as their own site/base URL, so some deep links/assets reached
> through the proxy may still point at the internal hostname. This URL
> is primarily meant to let you quickly confirm both apps are up and
> serving real pages (login screens, HTTP 200s) through one address,
> not as a production-grade ingress.

## Architecture

See `chart/templates/04-composition.yaml` for the full Crossplane
Composition. Key points:

- WordPress's OIDC plugin (`daggerhart-openid-connect-generic`) is
  configured with endpoint URLs hardcoded to `realms/setup` only — it
  cannot authenticate against any other Keycloak realm.
- The self-authored WordPress chart (`charts/wordpress/`) is packaged
  and served from an in-cluster classic Helm chart repository (plain
  HTTP, not OCI — see the note in `chart/templates/chart-registry.yaml`
  about a `provider-helm` OCI/TLS bug that this sidesteps).
- Secrets/ProviderConfigs/the demo Claim that depend on CRDs installed
  asynchronously by Crossplane's package manager are applied via a
  `post-install,post-upgrade` hook Job (`chart/templates/bootstrap-apply.yaml`)
  that polls for the CRDs before applying.
