#!/usr/bin/env bats

# Chart tests: helm template + assertions. Run from repo root: bats tests/chart-tests.bats
# Requires: helm, bats (bats-core)


setup_file() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  command -v helm >/dev/null || { echo "helm not found"; exit 1; }
  command -v yq >/dev/null || { echo "yq not found"; exit 1; }
}

ske_operator_config() {
  printf '%s\n' "$1" | yq 'select(.kind == "ConfigMap" and .metadata.name == "ske-operator").data.config'
}

@test "ske-gui OIDC with secretRef: does not create a secret" {
  run helm template test "$REPO_ROOT/ske-gui" \
    --set oidc.issuerUrl=https://example.com \
    --set oidc.clientId=client \
    --set oidc.secretRef.name=custom-secret
  [[ "$output" != *"kind: Secret"* ]]
}

@test "ske-gui OIDC with secretRef: deployment references given secret" {
  run helm template test "$REPO_ROOT/ske-gui" \
    --set oidc.issuerUrl=https://example.com \
    --set oidc.clientId=client \
    --set oidc.secretRef.name=custom-secret-name \
    --set oidc.secretRef.key=custom-secret-key
  local deployment=$(echo "$output" | yq '.spec.template.spec.containers[0].env[] | select(.name == "OIDC_CLIENT_SECRET")')

  # assert with yq
  [[ $(echo "$deployment" | yq '.valueFrom.secretKeyRef.name') == "custom-secret-name" ]]
  [[ $(echo "$deployment" | yq '.valueFrom.secretKeyRef.key') == "custom-secret-key" ]]
}

@test "ske-gui OIDC with inline clientSecret: headlamp-oidc-secret is created" {
  run helm template test "$REPO_ROOT/ske-gui" \
    --set oidc.issuerUrl=https://example.com \
    --set oidc.clientId=client \
    --set oidc.clientSecret=superSecret

  local deployment=$(echo "$output" | yq '.spec.template.spec.containers[0].env[] | select(.name == "OIDC_CLIENT_SECRET")')

  [[ "$output" == *"kind: Secret"* ]]
  [[ $(echo "$deployment" | yq '.valueFrom.secretKeyRef.name') == "headlamp-oidc-secret" ]]
  [[ $(echo "$deployment" | yq '.valueFrom.secretKeyRef.key') == "client-secret" ]]
}

@test "ske-operator releaseStorage.releasesPath: renders releasesPath in config" {
  run helm template test "$REPO_ROOT/ske-operator" \
    --set-string releaseStorage.releasesPath=platform-releases
  [ "$status" -eq 0 ]

  local config
  config="$(ske_operator_config "$output")"

  [[ $(printf '%s\n' "$config" | yq '.releaseStorage.releasesPath') == "platform-releases" ]]
  [[ $(printf '%s\n' "$config" | yq '.releaseStorage.path') == "null" ]]
}

@test "ske-operator releaseStorage.path: legacy key still renders releasesPath" {
  run helm template test "$REPO_ROOT/ske-operator" \
    --set-string releaseStorage.releasesPath= \
    --set-string releaseStorage.path=legacy-path
  [ "$status" -eq 0 ]

  local config
  config="$(ske_operator_config "$output")"

  [[ $(printf '%s\n' "$config" | yq '.releaseStorage.path') == "legacy-path" ]]
  [[ $(printf '%s\n' "$config" | yq '.releaseStorage.releasesPath') == "null" ]]
}

@test "ske-operator releaseStorage.path and releaseStorage.releasesPath: helm template fails" {
  run helm template test "$REPO_ROOT/ske-operator" \
    --set-string releaseStorage.path=legacy-path \
    --set-string releaseStorage.releasesPath=new-path

  [ "$status" -ne 0 ]
  [[ "$output" == *"releaseStorage.path and releaseStorage.releasesPath are mutually exclusive"* ]]
}
