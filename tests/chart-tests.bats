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
  [[ $(echo "$deployment" | yq '.valueFrom.secretKeyRef.key') == "clientSecret" ]]
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

@test "ske-operator imagePullSecret set: registry-secret is not rendered and deployments reference the given secret" {
  run helm template test "$REPO_ROOT/ske-operator" \
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

@test "ske-operator TLS certManager 'disabled=true': both secrets rendered when no secretRefs set" {
  run helm template test "$REPO_ROOT/ske-operator" \
    --set skeDeployment.tlsConfig.certManager.disabled=true \
    --set-string skeDeployment.tlsConfig.webhookCACert=ca \
    --set-string skeDeployment.tlsConfig.webhookTLSCert=cert \
    --set-string skeDeployment.tlsConfig.webhookTLSKey=key \
    --set-string skeDeployment.tlsConfig.metricsServerCACert=ca \
    --set-string skeDeployment.tlsConfig.metricsServerTLSCert=cert \
    --set-string skeDeployment.tlsConfig.metricsServerTLSKey=key
  [ "$status" -eq 0 ]
  local tls_secrets
  tls_secrets=$(printf '%s\n' "$output" | yq 'select(.kind == "Secret") | .metadata.name')
  [[ "$tls_secrets" == *"custom-kratix-platform-serving-cert"* ]]
  [[ "$tls_secrets" == *"custom-kratix-platform-metrics-server-cert"* ]]
}

@test "ske-operator TLS certManager 'disabled=true' and webhookTLSSecretRef is provided: webhook secret not created, configmap uses given name" {
  run helm template test "$REPO_ROOT/ske-operator" \
    --set skeDeployment.tlsConfig.certManager.disabled=true \
    --set skeDeployment.tlsConfig.webhookTLSSecretRef.name=my-webhook-tls-secret \
    --set-string skeDeployment.tlsConfig.metricsServerCACert=ca \
    --set-string skeDeployment.tlsConfig.metricsServerTLSCert=cert \
    --set-string skeDeployment.tlsConfig.metricsServerTLSKey=key
  [ "$status" -eq 0 ]
  local tls_secrets
  tls_secrets=$(printf '%s\n' "$output" | yq 'select(.kind == "Secret") | .metadata.name')
  [[ "$tls_secrets" != *"my-webhook-tls-secret"* ]]
  [[ "$tls_secrets" == *"custom-kratix-platform-metrics-server-cert"* ]]

  local cert_secret_name
  cert_secret_name=$(printf '%s\n' "$output" | yq 'select(.kind == "ConfigMap" and .metadata.name == "ske-deployment-config") | .data["ske-deployment"]' | yq '.spec.tlsConfig.certSecretName')
  [[ "$cert_secret_name" == "my-webhook-tls-secret" ]]
}

@test "ske-operator TLS certManager 'disabled=true' and metricsServerTLSSecretRef: metrics secret not created, configmap uses given name" {
  run helm template test "$REPO_ROOT/ske-operator" \
    --set skeDeployment.tlsConfig.certManager.disabled=true \
    --set-string skeDeployment.tlsConfig.webhookCACert=ca \
    --set-string skeDeployment.tlsConfig.webhookTLSCert=cert \
    --set-string skeDeployment.tlsConfig.webhookTLSKey=key \
    --set skeDeployment.tlsConfig.metricsServerTLSSecretRef.name=my-metrics-tls-secret
  [ "$status" -eq 0 ]
  local tls_secrets
  tls_secrets=$(printf '%s\n' "$output" | yq 'select(.kind == "Secret") | .metadata.name')
  [[ "$tls_secrets" == *"custom-kratix-platform-serving-cert"* ]]
  [[ "$tls_secrets" != *"my-metrics-tls-secret"* ]]

  local metrics_cert_secret_name
  metrics_cert_secret_name=$(printf '%s\n' "$output" | yq 'select(.kind == "ConfigMap" and .metadata.name == "ske-deployment-config") | .data["ske-deployment"]' | yq '.spec.tlsConfig.metricsServerCertSecretName')
  [[ "$metrics_cert_secret_name" == "my-metrics-tls-secret" ]]
}

@test "ske-operator TLS both secretRefs set: neither TLS secret created" {
  run helm template test "$REPO_ROOT/ske-operator" \
    --set skeDeployment.tlsConfig.certManager.disabled=true \
    --set skeDeployment.tlsConfig.webhookTLSSecretRef.name=my-webhook-tls-secret \
    --set skeDeployment.tlsConfig.metricsServerTLSSecretRef.name=my-metrics-tls-secret
  [ "$status" -eq 0 ]
  local tls_secrets
  tls_secrets=$(printf '%s\n' "$output" | yq 'select(.kind == "Secret") | .metadata.name')
  [[ "$tls_secrets" != *"my-webhook-tls-secret"* ]]
  [[ "$tls_secrets" != *"my-metrics-tls-secret"* ]]

  local metrics_cert_secret_name
  metrics_cert_secret_name=$(printf '%s\n' "$output" | yq 'select(.kind == "ConfigMap" and .metadata.name == "ske-deployment-config") | .data["ske-deployment"]' | yq '.spec.tlsConfig.metricsServerCertSecretName')
  [[ "$metrics_cert_secret_name" == "my-metrics-tls-secret" ]]

  local cert_secret_name
  cert_secret_name=$(printf '%s\n' "$output" | yq 'select(.kind == "ConfigMap" and .metadata.name == "ske-deployment-config") | .data["ske-deployment"]' | yq '.spec.tlsConfig.certSecretName')
  [[ "$cert_secret_name" == "my-webhook-tls-secret" ]]
}
