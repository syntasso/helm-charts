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

# --- ske-operator resources ---

cr_from_configmap() {
  # $1: rendered output, $2: configmap name, $3: data key
  echo "$1" | yq "select(.kind == \"ConfigMap\" and .metadata.name == \"$2\") | .data[\"$3\"]" | yq '.'
}

@test "ske-operator: default values keep the operator container limits" {
  run helm template test "$REPO_ROOT/ske-operator"
  local container=$(echo "$output" | yq 'select(.kind == "Deployment" and .metadata.name == "ske-operator-controller-manager") | .spec.template.spec.containers[0]')
  [[ $(echo "$container" | yq '.resources.limits.cpu') == "100m" ]]
  [[ $(echo "$container" | yq '.resources.limits.memory') == "256Mi" ]]
}

@test "ske-operator: limits set to null removes limits from the operator container" {
  run helm template test "$REPO_ROOT/ske-operator" \
    --set skeOperator.resources.limits=null
  local container=$(echo "$output" | yq 'select(.kind == "Deployment" and .metadata.name == "ske-operator-controller-manager") | .spec.template.spec.containers[0]')
  [[ $(echo "$container" | yq '.resources.limits') == "null" ]]
  [[ $(echo "$container" | yq '.resources.requests.cpu') == "100m" ]]
}

@test "ske-operator: null cpu limit renders the Kratix CR without a cpu limit" {
  run helm template test "$REPO_ROOT/ske-operator" \
    --set skeDeployment.deploymentConfig.resources.limits.cpu=null
  local cr=$(cr_from_configmap "$output" ske-deployment-config ske-deployment)
  [[ $(echo "$cr" | yq '.spec.deploymentConfig.resources.limits.cpu') == "null" ]]
  [[ $(echo "$cr" | yq '.spec.deploymentConfig.resources.limits.memory') == "256Mi" ]]
  [[ $(echo "$cr" | yq '.spec.deploymentConfig.resources.requests.cpu') == "100m" ]]
}

@test "ske-operator: null limits and requests render an empty resources block in the Kratix CR" {
  run helm template test "$REPO_ROOT/ske-operator" \
    --set skeDeployment.deploymentConfig.resources.limits=null \
    --set skeDeployment.deploymentConfig.resources.requests=null
  local cr=$(cr_from_configmap "$output" ske-deployment-config ske-deployment)
  [[ $(echo "$cr" | yq '.spec.deploymentConfig.resources') == "{}" ]]
}

@test "ske-operator: null limits and requests render an empty resources block for the platform manager" {
  run helm template test "$REPO_ROOT/ske-operator" \
    --set skeDeployment.platformManagerDeploymentConfig.resources.limits=null \
    --set skeDeployment.platformManagerDeploymentConfig.resources.requests=null
  local cr=$(cr_from_configmap "$output" ske-deployment-config ske-deployment)
  [[ $(echo "$cr" | yq '.spec.platformManagerDeploymentConfig.resources') == "{}" ]]
}

@test "ske-operator: null limits and requests render an empty resources block for an integration" {
  run helm template test "$REPO_ROOT/ske-operator" \
    --set portalIntegration.enabled=true \
    --set portalIntegration.deploymentConfig.resources.limits=null \
    --set portalIntegration.deploymentConfig.resources.requests=null
  local cr=$(cr_from_configmap "$output" portal-integration-config portal-integration)
  [[ $(echo "$cr" | yq '.spec.deploymentConfig.resources') == "{}" ]]
}

@test "ske-operator: post-install jobs use skeDeployment.deployJob.resources" {
  run helm template test "$REPO_ROOT/ske-operator" \
    --set portalIntegration.enabled=true \
    --set skeDeployment.deployJob.resources.limits.cpu=null
  for job in deploy-ske-deployment deploy-portal-integration; do
    local container=$(echo "$output" | yq "select(.kind == \"Job\" and .metadata.name == \"$job\") | .spec.template.spec.containers[0]")
    [[ $(echo "$container" | yq '.resources.limits.cpu') == "null" ]]
    [[ $(echo "$container" | yq '.resources.requests.cpu') == "100m" ]]
  done
}
