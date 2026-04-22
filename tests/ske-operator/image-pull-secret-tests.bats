#!/usr/bin/env bats

load helpers

# --- secret creation ---

@test "skeLicense set: registry secret is created with default imagePullSecret name" {
  run helm_ske_operator \
    --set skeLicense="abc123"
  [ "$status" -eq 0 ]

  local secret_name
  secret_name=$(printf '%s\n' "$output" | yq 'select(.kind == "Secret" and .type == "kubernetes.io/dockerconfigjson") | .metadata.name')
  [[ "$secret_name" == "syntasso-registry" ]]
}

@test "skeLicense set: registry secret uses custom imagePullSecret name" {
  run helm_ske_operator \
    --set skeLicense="abc123" \
    --set imageRegistry.imagePullSecret=myorg-secret
  [ "$status" -eq 0 ]

  local secret_name
  secret_name=$(printf '%s\n' "$output" | yq 'select(.kind == "Secret" and .type == "kubernetes.io/dockerconfigjson") | .metadata.name')
  [[ "$secret_name" == "myorg-secret" ]]
}

@test "skeLicense empty: registry secret is not created" {
  run helm_ske_operator \
    --set skeLicense=""
  [ "$status" -eq 0 ]

  local secret_name
  secret_name=$(printf '%s\n' "$output" | yq 'select(.kind == "Secret" and .type == "kubernetes.io/dockerconfigjson") | .metadata.name')
  [[ -z "$secret_name" ]]
}

@test "createRegistrySecret: false: registry secret is not created even when skeLicense is set" {
  run helm_ske_operator \
    --set skeLicense="abc123" \
    --set imageRegistry.createRegistrySecret=false
  [ "$status" -eq 0 ]

  local secret_name
  secret_name=$(printf '%s\n' "$output" | yq 'select(.kind == "Secret" and .type == "kubernetes.io/dockerconfigjson") | .metadata.name')
  [[ -z "$secret_name" ]]
}

@test "createRegistrySecret: false: registry secret is not created when imagePullSecret is also custom" {
  run helm_ske_operator \
    --set skeLicense="abc123" \
    --set imageRegistry.imagePullSecret=my-preexisting-secret \
    --set imageRegistry.createRegistrySecret=false
  [ "$status" -eq 0 ]

  local secret_name
  secret_name=$(printf '%s\n' "$output" | yq 'select(.kind == "Secret" and .type == "kubernetes.io/dockerconfigjson") | .metadata.name')
  [[ -z "$secret_name" ]]
}

@test "imagePullSecret empty: registry secret is not created even when skeLicense is set" {
  run helm_ske_operator \
    --set skeLicense="abc123" \
    --set imageRegistry.imagePullSecret=""
  [ "$status" -eq 0 ]

  local secret_name
  secret_name=$(printf '%s\n' "$output" | yq 'select(.kind == "Secret" and .type == "kubernetes.io/dockerconfigjson") | .metadata.name')
  [[ -z "$secret_name" ]]
}

# --- imagePullSecrets on workloads ---

@test "imagePullSecret set: operator deployment references it" {
  run helm_ske_operator \
    --set imageRegistry.imagePullSecret=syntasso-registry \
    --set skeLicense="abc123"
  [ "$status" -eq 0 ]

  local pull_secret
  pull_secret=$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment") | .spec.template.spec.imagePullSecrets[].name')
  [[ "$pull_secret" == *"syntasso-registry"* ]]
}

@test "imagePullSecret set: deploy-ske-deployment job references it" {
  run helm_ske_operator \
    --set imageRegistry.imagePullSecret=syntasso-registry \
    --set skeLicense="abc123"
  [ "$status" -eq 0 ]

  local pull_secret
  pull_secret=$(printf '%s\n' "$output" | yq 'select(.kind == "Job" and .metadata.name == "deploy-ske-deployment") | .spec.template.spec.imagePullSecrets[].name')
  [[ "$pull_secret" == "syntasso-registry" ]]
}

@test "imagePullSecret set: backstage job references it" {
  run helm_ske_operator \
    --set imageRegistry.imagePullSecret=syntasso-registry \
    --set skeLicense="abc123" \
    --set backstageIntegration.enabled=true \
    --set backstageIntegration.version=v0.6.0
  [ "$status" -eq 0 ]

  local pull_secret
  pull_secret=$(printf '%s\n' "$output" | yq 'select(.kind == "Job" and .metadata.name == "deploy-backstage-integration") | .spec.template.spec.imagePullSecrets[].name')
  [[ "$pull_secret" == "syntasso-registry" ]]
}

@test "imagePullSecret set: cortex job references it" {
  run helm_ske_operator \
    --set imageRegistry.imagePullSecret=syntasso-registry \
    --set skeLicense="abc123" \
    --set cortexIntegration.enabled=true \
    --set cortexIntegration.config.integrationAlias=test \
    --set cortexIntegration.config.provider=github \
    --set cortexIntegration.config.repositoryName=test/repo \
    --set cortexIntegration.config.token=mytoken \
    --set cortexIntegration.config.url=https://cortex.example.com
  [ "$status" -eq 0 ]

  local pull_secret
  pull_secret=$(printf '%s\n' "$output" | yq 'select(.kind == "Job" and .metadata.name == "deploy-cortex-integration") | .spec.template.spec.imagePullSecrets[].name')
  [[ "$pull_secret" == "syntasso-registry" ]]
}

@test "imagePullSecret empty: no imagePullSecrets on operator deployment" {
  run helm_ske_operator \
    --set imageRegistry.imagePullSecret="" \
    --set skeLicense="abc123"
  [ "$status" -eq 0 ]

  local pull_secrets
  pull_secrets=$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment") | .spec.template.spec.imagePullSecrets[].name')
  [[ -z "$pull_secrets" ]]
}

@test "imagePullSecret empty: no imagePullSecrets on any job" {
  run helm_ske_operator \
    --set imageRegistry.imagePullSecret="" \
    --set skeLicense="abc123" \
    --set backstageIntegration.enabled=true \
    --set backstageIntegration.version=v0.6.0 \
    --set cortexIntegration.enabled=true \
    --set cortexIntegration.config.integrationAlias=test \
    --set cortexIntegration.config.provider=github \
    --set cortexIntegration.config.repositoryName=test/repo \
    --set cortexIntegration.config.token=mytoken \
    --set cortexIntegration.config.url=https://cortex.example.com
  [ "$status" -eq 0 ]

  local pull_secrets
  pull_secrets=$(printf '%s\n' "$output" | yq 'select(.kind == "Job") | .spec.template.spec.imagePullSecrets[].name')
  [[ -z "$pull_secrets" ]]
}

# --- createRegistrySecret: false still injects the secret name into workloads ---

@test "createRegistrySecret: false: workloads still reference the imagePullSecret name" {
  run helm_ske_operator \
    --set skeLicense="abc123" \
    --set imageRegistry.imagePullSecret=my-preexisting-secret \
    --set imageRegistry.createRegistrySecret=false
  [ "$status" -eq 0 ]

  local deployment_secret
  deployment_secret=$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment") | .spec.template.spec.imagePullSecrets[].name')
  [[ "$deployment_secret" == "my-preexisting-secret" ]]

  local job_secret
  job_secret=$(printf '%s\n' "$output" | yq 'select(.kind == "Job" and .metadata.name == "deploy-ske-deployment") | .spec.template.spec.imagePullSecrets[].name')
  [[ "$job_secret" == "my-preexisting-secret" ]]
}

# --- operator-config configmap ---

@test "operator-config: pullSecret reflects imagePullSecret value" {
  run helm_ske_operator \
    --set imageRegistry.imagePullSecret=my-custom-secret \
    --set skeLicense="abc123"
  [ "$status" -eq 0 ]

  local pull_secret
  pull_secret=$(printf '%s\n' "$output" | \
    yq 'select(.kind == "ConfigMap" and .metadata.name == "ske-operator") | .data.config' | \
    yq '.imageRegistry.pullSecret')
  [[ "$pull_secret" == "my-custom-secret" ]]
}

@test "operator-config: pullSecret is empty when imagePullSecret is empty" {
  run helm_ske_operator \
    --set imageRegistry.imagePullSecret="" \
    --set skeLicense="abc123"
  [ "$status" -eq 0 ]

  local pull_secret
  pull_secret=$(printf '%s\n' "$output" | \
    yq 'select(.kind == "ConfigMap" and .metadata.name == "ske-operator") | .data.config' | \
    yq '.imageRegistry.pullSecret')
  [[ -z "$pull_secret" ]]
}
