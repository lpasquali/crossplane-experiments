{{/*
Vault-backed secret trio, used by chart/manifests/composition.yaml (which
is loaded via `tpl`, so named templates defined here are available to it
too). Every password/secret this demo generates is written into Vault
(single source of truth) via provider-vault's SecretV2, then read back
out by External Secrets Operator into the exact Secret name/keys the
existing consumers (Helm chart values, provider-kubernetes Objects)
already expect -- zero changes needed downstream.

Produces 3 composed resources:
  1. "<id>-vault-source" - a plain Secret (crossplane-system namespace)
     holding a single JSON-blob key built from the composite's fields.
  2. "<id>-vault-write"  - provider-vault SecretV2, pushes that JSON
     blob into Vault at <vaultPath> under the shared KV-v2 mount.
  3. "<id>-vault-sync"   - ExternalSecret (ESO), reads the same Vault
     path back out, expanding the JSON blob's keys into the final
     Secret <secretName>/<secretNamespace>.

Call with a dict:
  id              unique id, used to name the staging resources
  secretName      final Kubernetes Secret name consumers expect
  secretNamespace namespace of the final Secret
  vaultPath       path under the KV-v2 mount, e.g. "wordpress/admin"
  jsonFmt         fmt string with one %s per entry in `fields`
  fields          list of composite fromFieldPath values, in order
  Release         pass through .Release
  Values          pass through .Values
*/}}
{{- define "crossplane-experiments.vaultBackedSecret" -}}
- name: {{ .id }}-vault-source
  base:
    apiVersion: kubernetes.crossplane.io/v1alpha1
    kind: Object
    spec:
      providerConfigRef:
        name: default
      forProvider:
        manifest:
          apiVersion: v1
          kind: Secret
          metadata:
            name: {{ .id }}-vault-source
            namespace: {{ .Release.Namespace }}
          type: Opaque
          stringData:
            data.json: ""
  patches:
    - type: CombineFromComposite
      combine:
        variables:
{{- range .fields }}
          - fromFieldPath: {{ . }}
{{- end }}
        strategy: string
        string:
          fmt: {{ .jsonFmt | quote }}
      toFieldPath: spec.forProvider.manifest.stringData['data.json']

- name: {{ .id }}-vault-write
  base:
    apiVersion: kv.vault.upbound.io/v1alpha1
    kind: SecretV2
    spec:
      providerConfigRef:
        name: default
      forProvider:
        mount: {{ .Values.vaultSecrets.mount }}
        name: {{ .vaultPath }}
        dataJsonSecretRef:
          name: {{ .id }}-vault-source
          namespace: {{ .Release.Namespace }}
          key: data.json

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
