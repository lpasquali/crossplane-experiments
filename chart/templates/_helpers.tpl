{{/*
Vault-backed secret, used by chart/manifests/composition.yaml (which is
loaded via `tpl`, so named templates defined here are available to it
too).

Vault is the actual source of truth for every password/secret this demo
uses -- nothing in the Composite/Claim or in Helm values ever carries a
plaintext secret value. Each of these Vault paths is populated ONCE, by
a seeding step in the bootstrap-apply Job (chart/templates/bootstrap-apply.yaml)
that writes a random value only if the path doesn't already have one
(idempotent across `helm upgrade`, and overridable per-path for
CI/reproducible-demo purposes via .Values.vaultSecrets.seedOverrides --
see README's "Changing a vaulted secret's value" section for why you
can't just edit the value in Vault's UI afterwards instead).

This helper only does the read-back half: an ExternalSecret (ESO) pulls
the already-seeded value out of Vault and expands its JSON keys into
the final Secret name/keys the existing consumers (Helm chart values,
provider-kubernetes Objects) already expect.

Call with a dict:
  id              unique id, used to name the ExternalSecret
  secretName      final Kubernetes Secret name consumers expect
  secretNamespace namespace of the final Secret
  vaultPath       path under the KV-v2 mount, e.g. "wordpress/admin"
*/}}
{{- define "crossplane-experiments.vaultBackedSecret" -}}
- name: {{ .id }}-vault-sync
  base:
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: {{ .id }}-vault-sync
      namespace: {{ .secretNamespace }}
    spec:
      refreshInterval: 1m
      secretStoreRef:
        name: vault-backend
        kind: ClusterSecretStore
      target:
        name: {{ .secretName }}
        creationPolicy: Owner
      dataFrom:
        - extract:
            key: {{ .vaultPath }}
{{- end -}}
