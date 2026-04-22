#!/usr/bin/env bats

load helpers

# ---------------------------------------------------------------------------
# Scenario 1: no pull secret (managePullSecret: false, imagePullSecret unset)
# The chart creates no secret and injects no imagePullSecrets anywhere.
# ---------------------------------------------------------------------------

@test "scenario 1: no pull secret: no secret created" {
  run helm_ske_operator \
    --set skeLicense="" \
    --set imageRegistry.imagePullSecret=""
  [ "$status" -eq 0 ]

  local secret_name
  secret_name=$(printf '%s\n' "$output" | yq 'select(.kind == "Secret" and .type == "kubernetes.io/dockerconfigjson") | .metadata.name')
  [[ -z "$secret_name" ]]
}

@test "scenario 1: no pull secret: no imagePullSecrets on deployment" {
  run helm_ske_operator \
    --set skeLicense="" \
    --set imageRegistry.imagePullSecret=""
  [ "$status" -eq 0 ]

  local pull_secrets
  pull_secrets=$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment") | .spec.template.spec.imagePullSecrets[].name')
  [[ -z "$pull_secrets" ]]
}

@test "scenario 1: no pull secret: no imagePullSecrets on any job" {
  run helm_ske_operator \
    --set skeLicense="" \
    --set imageRegistry.imagePullSecret="" \
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

@test "scenario 1: no pull secret: operator-config pullSecret is empty" {
  run helm_ske_operator \
    --set skeLicense="" \
    --set imageRegistry.imagePullSecret=""
  [ "$status" -eq 0 ]

  local pull_secret
  pull_secret=$(ske_operator_config "$output" | yq '.imageRegistry.pullSecret')
  [[ -z "$pull_secret" ]]
}

@test "scenario 1: managePullSecret false with skeLicense: no secret created, no injection" {
  run helm_ske_operator \
    --set skeLicense="abc123" \
    --set imageRegistry.managePullSecret=false
  [ "$status" -eq 0 ]

  local secret_name
  secret_name=$(printf '%s\n' "$output" | yq 'select(.kind == "Secret" and .type == "kubernetes.io/dockerconfigjson") | .metadata.name')
  [[ -z "$secret_name" ]]

  local pull_secrets
  pull_secrets=$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment") | .spec.template.spec.imagePullSecrets[].name')
  [[ -z "$pull_secrets" ]]
}

# ---------------------------------------------------------------------------
# Scenario 2: pre-created secret (managePullSecret: false, imagePullSecret set)
# The chart injects the given name everywhere and does not create a secret.
# ---------------------------------------------------------------------------

@test "scenario 2: managePullSecret false, imagePullSecret set: no secret created" {
  run helm_ske_operator \
    --set skeLicense="" \
    --set imageRegistry.imagePullSecret=my-secret
  [ "$status" -eq 0 ]

  local secret_name
  secret_name=$(printf '%s\n' "$output" | yq 'select(.kind == "Secret" and .type == "kubernetes.io/dockerconfigjson") | .metadata.name')
  [[ -z "$secret_name" ]]
}

@test "scenario 2: managePullSecret false, imagePullSecret set: operator deployment references it" {
  run helm_ske_operator \
    --set skeLicense="" \
    --set imageRegistry.imagePullSecret=my-secret
  [ "$status" -eq 0 ]

  local pull_secret
  pull_secret=$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment") | .spec.template.spec.imagePullSecrets[].name')
  [[ "$pull_secret" == "my-secret" ]]
}

@test "scenario 2: managePullSecret false, imagePullSecret set: all jobs reference it" {
  run helm_ske_operator \
    --set skeLicense="" \
    --set imageRegistry.imagePullSecret=my-secret \
    --set backstageIntegration.enabled=true \
    --set backstageIntegration.version=v0.6.0 \
    --set cortexIntegration.enabled=true \
    --set cortexIntegration.config.integrationAlias=test \
    --set cortexIntegration.config.provider=github \
    --set cortexIntegration.config.repositoryName=test/repo \
    --set cortexIntegration.config.token=mytoken \
    --set cortexIntegration.config.url=https://cortex.example.com
  [ "$status" -eq 0 ]

  local ske_job backstage_job cortex_job
  ske_job=$(printf '%s\n' "$output" | yq 'select(.kind == "Job" and .metadata.name == "deploy-ske-deployment") | .spec.template.spec.imagePullSecrets[].name')
  backstage_job=$(printf '%s\n' "$output" | yq 'select(.kind == "Job" and .metadata.name == "deploy-backstage-integration") | .spec.template.spec.imagePullSecrets[].name')
  cortex_job=$(printf '%s\n' "$output" | yq 'select(.kind == "Job" and .metadata.name == "deploy-cortex-integration") | .spec.template.spec.imagePullSecrets[].name')
  [[ "$ske_job" == "my-secret" ]]
  [[ "$backstage_job" == "my-secret" ]]
  [[ "$cortex_job" == "my-secret" ]]
}

@test "scenario 2: managePullSecret false, imagePullSecret set: operator-config reflects it" {
  run helm_ske_operator \
    --set skeLicense="" \
    --set imageRegistry.imagePullSecret=my-secret
  [ "$status" -eq 0 ]

  local pull_secret
  pull_secret=$(ske_operator_config "$output" | yq '.imageRegistry.pullSecret')
  [[ "$pull_secret" == "my-secret" ]]
}

@test "scenario 2: managePullSecret false with skeLicense set: no secret created, imagePullSecret injected" {
  run helm_ske_operator \
    --set skeLicense="abc123" \
    --set imageRegistry.managePullSecret=false \
    --set imageRegistry.imagePullSecret=my-preexisting-secret
  [ "$status" -eq 0 ]

  local secret_name
  secret_name=$(printf '%s\n' "$output" | yq 'select(.kind == "Secret" and .type == "kubernetes.io/dockerconfigjson") | .metadata.name')
  [[ -z "$secret_name" ]]

  local pull_secret
  pull_secret=$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment") | .spec.template.spec.imagePullSecrets[].name')
  [[ "$pull_secret" == "my-preexisting-secret" ]]
}

# ---------------------------------------------------------------------------
# Scenario 3: chart-managed secret (skeLicense set, managePullSecret unset or true)
# The chart creates "syntasso-registry" and injects it into all workloads.
# imagePullSecret is ignored.
# ---------------------------------------------------------------------------

@test "scenario 3: skeLicense set: creates secret named syntasso-registry" {
  run helm_ske_operator \
    --set skeLicense="abc123"
  [ "$status" -eq 0 ]

  local secret_name
  secret_name=$(printf '%s\n' "$output" | yq 'select(.kind == "Secret" and .type == "kubernetes.io/dockerconfigjson") | .metadata.name')
  [[ "$secret_name" == "syntasso-registry" ]]
}

@test "scenario 3: skeLicense set: operator deployment uses syntasso-registry" {
  run helm_ske_operator \
    --set skeLicense="abc123"
  [ "$status" -eq 0 ]

  local pull_secret
  pull_secret=$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment") | .spec.template.spec.imagePullSecrets[].name')
  [[ "$pull_secret" == "syntasso-registry" ]]
}

@test "scenario 3: skeLicense set: all jobs use syntasso-registry" {
  run helm_ske_operator \
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

  local ske_job backstage_job cortex_job
  ske_job=$(printf '%s\n' "$output" | yq 'select(.kind == "Job" and .metadata.name == "deploy-ske-deployment") | .spec.template.spec.imagePullSecrets[].name')
  backstage_job=$(printf '%s\n' "$output" | yq 'select(.kind == "Job" and .metadata.name == "deploy-backstage-integration") | .spec.template.spec.imagePullSecrets[].name')
  cortex_job=$(printf '%s\n' "$output" | yq 'select(.kind == "Job" and .metadata.name == "deploy-cortex-integration") | .spec.template.spec.imagePullSecrets[].name')
  [[ "$ske_job" == "syntasso-registry" ]]
  [[ "$backstage_job" == "syntasso-registry" ]]
  [[ "$cortex_job" == "syntasso-registry" ]]
}

@test "scenario 3: skeLicense set: imagePullSecret value is ignored" {
  run helm_ske_operator \
    --set skeLicense="abc123" \
    --set imageRegistry.imagePullSecret=some-other-secret
  [ "$status" -eq 0 ]

  local pull_secret
  pull_secret=$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment") | .spec.template.spec.imagePullSecrets[].name')
  [[ "$pull_secret" == "syntasso-registry" ]]
}

@test "scenario 3: skeLicense set: operator-config pullSecret is syntasso-registry" {
  run helm_ske_operator \
    --set skeLicense="abc123"
  [ "$status" -eq 0 ]

  local pull_secret
  pull_secret=$(ske_operator_config "$output" | yq '.imageRegistry.pullSecret')
  [[ "$pull_secret" == "syntasso-registry" ]]
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

@test "managePullSecret: true without skeLicense: helm template fails with clear error" {
  run helm_ske_operator \
    --set skeLicense="" \
    --set imageRegistry.managePullSecret=true
  [ "$status" -ne 0 ]
  [[ "$output" == *"managePullSecret is true but skeLicense is not set"* ]]
}
