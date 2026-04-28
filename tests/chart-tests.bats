#!/usr/bin/env bats

# Chart tests: helm template + assertions. Run from repo root: bats tests/chart-tests.bats
# Requires: helm, bats (bats-core), yq

setup_file() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  command -v helm >/dev/null || { echo "helm not found"; exit 1; }
  command -v yq >/dev/null || { echo "yq not found"; exit 1; }
}

# --- ske-gui ---

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
  [[ $(echo "$deployment" | yq '.valueFrom.secretKeyRef.key') == "clientSecret" ]]
}

# --- k8s-health-agent ---

@test "k8s-health-agent imagePullSecret set: registry-secret is not rendered and deployment references the given secret" {
  run helm template test "$REPO_ROOT/k8s-health-agent" \
    --set imageRegistry.imagePullSecret=my-existing-pull-secret \
    --set skeLicense=""
  [ "$status" -eq 0 ]
  local secrets
  secrets=$(printf '%s\n' "$output" | yq 'select(.kind == "Secret") | .metadata.name')
  [[ "$secrets" != *"syntasso-registry"* ]]
  local pull_secrets
  pull_secrets=$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment") | .spec.template.spec.imagePullSecrets[].name')
  [[ "$pull_secrets" == *"my-existing-pull-secret"* ]]
  [[ "$pull_secrets" != *"syntasso-registry"* ]]
}
