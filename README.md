# crossplane-experiments

A single Helm "umbrella" chart that stands up a complete demo of a
Crossplane Composition provisioning **WordPress + Keycloak + MariaDB
(for WordPress) + PostgreSQL (for Keycloak)**, with WordPress
authenticating exclusively against Keycloak's `setup` realm via OIDC.

Every password/secret this demo uses (DB passwords, Keycloak admin
password, etc) is generated and stored **only in HashiCorp Vault** —
never in the Crossplane Claim, in Helm values, or anywhere else
plaintext-readable via `kubectl get -o yaml`/`helm get values`. A
one-time idempotent seeding step (part of the `bootstrap-apply` hook
Job) writes a random value into each Vault path the first time it's
missing; the **External Secrets Operator** then continuously pulls
those values out of Vault into native Kubernetes Secrets for every
consumer to read, same as before.

No Bitnami images/charts are used anywhere. Every component is either
an official upstream chart/image or self-authored:

| Component            | Source                                                    |
|-----------------------|------------------------------------------------------------|
| Crossplane            | `https://charts.crossplane.io/stable` (official)           |
| CloudNativePG         | `https://cloudnative-pg.github.io/charts` (official)        |
| mariadb-operator      | `oci://ghcr.io/mariadb-operator/charts` (official)          |
| HashiCorp Vault       | `https://helm.releases.hashicorp.com` (official, dev-mode)  |
| External Secrets Operator | `https://charts.external-secrets.io` (official, CNCF)   |
| Keycloak              | `codecentric/keycloakx` chart, `quay.io/keycloak/keycloak` image |
| WordPress             | self-authored chart (`charts/wordpress/`), official `wordpress` image |
| Chart registry        | plain `nginx:1.27-alpine` serving a classic Helm chart repo |
| Reverse proxy          | plain `nginx:1.27-alpine`, self-signed TLS                  |

## One-command install

```bash
./scripts/deploy.sh
```

This creates the kind cluster `cnpg-crossplane` (if it doesn't already
exist, using `kind-config.yaml` - includes the port mapping used by the
reverse-proxy URL below), (re)packages the self-authored WordPress chart,
refreshes the umbrella chart's Helm dependencies, and
`helm upgrade --install`s everything: Crossplane, CloudNativePG,
mariadb-operator, providers, the XRD/Composition, the in-cluster chart
registry, the reverse proxy, and (by default) a demo claim instantiating
the full WordPress+Keycloak+MariaDB+Postgres stack. It's safe to re-run
any time you change something - the cluster is reused and the Helm
release is upgraded in place. Any extra arguments are passed straight
through to `helm upgrade --install` (e.g. `./scripts/deploy.sh --debug`).

To tear everything down (deletes the kind cluster entirely - the demo
has no state outside it, since Vault runs in dev/in-memory mode):

```bash
./scripts/destroy.sh
```

Equivalently, by hand:

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
exposing everything under one address. All of these URLs are also
printed by `helm install`/`helm upgrade` itself (see
`chart/templates/NOTES.txt`), so you don't need to hunt for them here:

```mermaid
flowchart LR
    Browser(("🌐 Your browser"))
    Browser == "https://crossplane-experiment:9443" ==> Proxy["Reverse proxy\n(nginx, self-signed TLS)"]

    Proxy -- "/wordpress" --> WP["WordPress\nOIDC login via Keycloak's 'setup' realm"]
    Proxy -- "/keycloak" --> KC["Keycloak\nmaster realm admin console"]
    Proxy -. "/keycloak-&lt;realm&gt;\n(302 redirect)" .-> KC
    Proxy -. "/vault\n(302 redirect)" .-> UI
    Proxy -- "/ui/, /v1/" --> UI["Vault UI + API\n(dev-mode root token: see helm output)"]

    WP -. "OIDC login" .-> KC
```

- `https://crossplane-experiment:9443/wordpress` -> WordPress
  (OIDC login via Keycloak's `setup` realm)
- `https://crossplane-experiment:9443/keycloak` -> Keycloak
  (master realm admin console / general access)
- `https://crossplane-experiment:9443/keycloak-faggeta` -> a
  client-side (302) redirect straight to
  `https://crossplane-experiment:9443/keycloak/admin/faggeta/console`,
  i.e. the Keycloak `faggeta` realm's admin console, still served
  through the same `/keycloak` proxy path above
- `https://crossplane-experiment:9443/vault` -> a client-side (302)
  redirect to Vault's UI at `/ui/` (dev-mode root token is `root` — see
  "Changing a vaulted secret's value directly in the Vault UI" below
  before editing anything there)
- `https://crossplane-experiment:9443/ui/` and `/v1/` -> Vault's UI
  and API directly (Vault hardcodes these absolute paths itself, so
  unlike WordPress/Keycloak it can't be rebased under a `/vault`
  prefix — see the note in `reverse-proxy-nginx.conf.template`)

External Secrets Operator ships no web UI of its own; inspect its
objects instead with `kubectl get/describe externalsecret,clustersecretstore`.

To reach it from your host:

1. Add a hosts entry (or just use `localhost`):
   ```
   echo "127.0.0.1 crossplane-experiment" | sudo tee -a /etc/hosts
   ```
2. Make sure the kind cluster was created with `kind-config.yaml`
   (maps host port `9443` -> the reverse proxy's NodePort `30443`).
3. Browse to any of the URLs above (accept the self-signed certificate
   warning).

> Note: the proxy preserves each app's full path prefix (`/wordpress`,
> `/keycloak`) all the way to the backend instead of stripping it, and
> both apps are configured to know they're mounted at that prefix —
> WordPress's Apache has a matching `Alias` (see
> `charts/wordpress/templates/apache-subpath-configmap.yaml`) and
> Keycloak's `http.relativePath` is set to `/keycloak` (see
> `composition.yaml`). This matters because both apps generate their
> own redirects (e.g. Apache's `mod_dir` adding a trailing slash to
> `/wordpress/wp-admin`, or Keycloak adding one to
> `/keycloak/admin/<realm>/console`) using whatever path prefix and
> Host header *they* were given — if the proxy had stripped the
> prefix or passed the internal Service hostname, those self-generated
> redirects would point at an unreachable internal/prefix-less URL.
> The proxy also passes through the real external `Host` header
> (`$http_host`, not a hardcoded internal DNS name) and rewrites any
> plain-`http://` redirect the backends emit back to `https://` via
> `proxy_redirect` (neither Apache nor Keycloak know TLS is terminated
> upstream by the proxy, since the proxy-to-backend hop is plain HTTP).
> Vault's UI is the one exception: it hardcodes its own absolute
> `/ui/`/`/v1/` paths with no equivalent of a configurable prefix, so
> it's proxied at those exact paths instead of under `/vault`.

## Architecture

See `chart/templates/04-composition.yaml` for the full Crossplane
Composition. Key points:

```mermaid
flowchart TB
    subgraph Helm["Umbrella Helm chart (crossplane-experiments)"]
        XP["Crossplane"]
        CNPG["CloudNativePG operator"]
        MDBOP["mariadb-operator"]
        VAULT["HashiCorp Vault (dev mode)"]
        ESO["External Secrets Operator"]
        REG["In-cluster chart registry (nginx)"]
        PROXY["Reverse proxy (nginx, TLS)"]
    end

    subgraph XRD["Crossplane Composition pipeline (XAppEnvironment)"]
        ES["ExternalSecret\n(reads Vault-seeded creds)"]
        KCPG["CloudNativePG Cluster\n(Keycloak DB)"]
        KC["Keycloak Helm Release\n(codecentric/keycloakx)"]
        REALM["Realm / User / Client / Role\n(provider-keycloak)"]
        WPDB["MariaDB (mariadb-operator)\n(WordPress DB)"]
        WP["WordPress Helm Release\n(self-authored chart)"]
    end

    SEED["bootstrap-apply Job:\nseed Vault if path absent"]

    SEED -- "random value, first run only" --> VAULT
    VAULT -- "read via ClusterSecretStore" --> ESO
    ESO --> ES
    ES -- "K8s Secret" --> KCPG
    ES -- "K8s Secret" --> KC
    ES -- "K8s Secret" --> WPDB

    KCPG -- "Postgres" --> KC
    KC -- "OIDC (realms/setup only)" --> WP
    REALM -- "configures" --> KC
    WPDB -- "MariaDB" --> WP

    REG -- "serves WordPress chart" --> XP
    XP -- "reconciles" --> XRD

    PROXY -- "/wordpress" --> WP
    PROXY -- "/keycloak" --> KC
    PROXY -- "/ui/, /v1/" --> VAULT

    User(("Browser")) -- "https://crossplane-experiment:9443" --> PROXY
```

- Vault is the actual source of truth for every password/secret this
  demo uses — not the Claim, not Helm values. The `bootstrap-apply` hook
  Job seeds each Vault path with a random value exactly once (only if
  that path has no data yet, so `helm upgrade` never rotates/clobbers
  an existing deployment's secrets); the Composition then only ever
  *reads* from Vault, via an `ExternalSecret` backed by ESO's
  `ClusterSecretStore` (`vault-backend`) — see the `vaultBackedSecret`
  helper in `chart/templates/_helpers.tpl`, the seeding script and
  ProviderConfig/ClusterSecretStore wiring in
  `chart/templates/bootstrap-apply.yaml`, and `vaultSecrets.seedOverrides`
  in `chart/values.yaml` if you need a pinned (non-random) value for
  CI/reproducibility. This keeps every existing consumer (Helm chart
  values, `provider-kubernetes` Objects) reading a plain Secret,
  unchanged.
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

### Changing a vaulted secret's value directly in the Vault UI

Every secret in the table above (`keycloak/db-credentials`,
`keycloak/admin-secret`, `keycloak/demo-user-password`,
`wordpress/oidc-client-secret`, `wordpress/mariadb-credentials`,
`wordpress/admin-secret`) is reachable and editable through the Vault
UI (`/vault` or `/ui/`, see "Single external URL" above). Vault really
is this demo's only source of truth for these values now — there's no
Crossplane push loop to revert your edit. **What happens next if you
edit one, however, differs by secret**, for cybersecurity awareness
here's exactly why, tracing the actual data flow:

```
bootstrap-apply Job (one-time, only if path has no data yet)
   --(random value, or vaultSecrets.seedOverrides.* if set)-->
Vault KV path (e.g. keycloak/db-credentials)   <-- you'd edit here
   --(ExternalSecret, refreshInterval: 1m, pull-only)-->
Kubernetes Secret actually consumed by the app (e.g. keycloak-db-credentials)
   --(see below: either auto-rotated, or read once at pod start)-->
the running Postgres role password / MariaDB user password / app's in-memory config
```

Within about a minute of any Vault edit, the `ExternalSecret` pulls
your edited value and overwrites the consumer Kubernetes `Secret` with
it, and it **stays there** (nothing pushes the old value back anymore).
What happens after that depends on which secret you changed:

#### `keycloak/db-credentials` and `wordpress/mariadb-credentials` — **auto-rotated**

These two are the only secrets with native operator-level support for
continuous password reconciliation, so this demo wires it up end to
end — editing either of these in Vault **does** rotate the real,
live database credential, with no manual steps or restarts required:

- `keycloak-db-credentials` carries a `cnpg.io/reload: "true"` label
  (added via `vaultBackedSecret`'s `extraLabels`), which makes
  CloudNativePG reconcile immediately on any change to the Secret. A
  dedicated `DatabaseRole` resource (`keycloak-postgres-role` in
  `composition.yaml`, a `postgresql.cnpg.io/v1 DatabaseRole` applied
  via `provider-kubernetes`) continuously watches that same Secret and
  runs `ALTER ROLE ... PASSWORD ...` against the live `keycloak`
  Postgres role whenever it changes.
- `wordpress-mariadb-credentials` carries a `k8s.mariadb.com/watch:
  "true"` label, which mariadb-operator's `MariaDB` CR natively
  understands for its inline `passwordSecretKeyRef` — it watches the
  Secret and runs `ALTER USER ... IDENTIFIED BY ...` against the live
  MariaDB user whenever it changes.
- In both cases this is **credential rotation only** — the already
  established connections in a running Postgres/WordPress pod session
  aren't forcibly dropped, but any new connection (including the next
  one a restarted pod makes) must use the new password. No
  CrashLoopBackOff risk for *this* pair of secrets.
- MariaDB's **root** password (`rootPasswordSecretKeyRef`) has no
  equivalent watch-support in mariadb-operator, so it is intentionally
  **not** part of this rotation path — only the WordPress application
  user is automated.

#### Every other secret (`keycloak/admin-secret`, `keycloak/demo-user-password`, `wordpress/oidc-client-secret`, `wordpress/admin-secret`) — **manual rotation + restart required**

Keycloak and WordPress only read these as environment variables at pod
startup — there is no operator watching them for live changes. If you
edit one of these in Vault:

1. **The actual credential never rotates on its own.** Neither
   Keycloak's admin/demo-user password, the OIDC client secret, nor
   WordPress's admin password changes just because the Vault value
   changed — only the Kubernetes `Secret` does.
2. **This can cause an outage with no real security benefit on its
   own**: if the affected pod happens to restart while your edited
   (now-mismatched) value is live in its Secret, it will try to
   authenticate with the wrong credential and fail/crash-loop until
   you either revert the Vault value or manually rotate the real
   credential to match.

**To actually rotate one of these**, edit the value in Vault (or
`kubectl delete secret <consumer-secret>` to force an immediate
`ExternalSecret` re-sync) **and** separately rotate the real credential
through Keycloak's own admin API/console, **and** restart the
consumer pod so it picks up the new value — so both stay in sync.
This demo has no automation for these; it's left as an exercise for a
production-grade follow-up (e.g. a Keycloak `User`/`Client` reconciler
equivalent to CNPG's `DatabaseRole`, if/when `provider-keycloak`
grows one).

