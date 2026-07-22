#!/usr/bin/env bats

load helpers

@test "SKE Operator certManager disabled: inline TLS values populate all webhook CA bundles" {
  run helm_ske_operator \
    --set global.skeOperator.tlsConfig.certManager.disabled=true \
    --set-string global.skeOperator.tlsConfig.webhookCACert=ca \
    --set-string global.skeOperator.tlsConfig.webhookTLSCert=cert \
    --set-string global.skeOperator.tlsConfig.webhookTLSKey=key
  [ "$status" -eq 0 ]

  local webhook_ca_bundles
  webhook_ca_bundles=$(printf '%s\n' "$output" | yq 'select(.kind == "ValidatingWebhookConfiguration") | .webhooks[].clientConfig.caBundle')
  [[ "$webhook_ca_bundles" == $'Y2E=\nY2E=' ]]

  local conversion_ca_bundle
  conversion_ca_bundle=$(printf '%s\n' "$output" | yq 'select(.kind == "CustomResourceDefinition" and .metadata.name == "kratixes.platform.syntasso.io") | .spec.conversion.webhook.clientConfig.caBundle')
  [[ "$conversion_ca_bundle" == "Y2E=" ]]

  local operator_tls_secret
  operator_tls_secret=$(printf '%s\n' "$output" | yq 'select(.kind == "Secret" and .metadata.name == "ske-operator-webhook-server-cert") | .metadata.name')
  [[ "$operator_tls_secret" == "ske-operator-webhook-server-cert" ]]
}

@test "SKE Operator webhookTLSSecretRef: reports a missing pre-existing Secret" {
  run helm_ske_operator \
    --set global.skeOperator.tlsConfig.certManager.disabled=true \
    --set global.skeOperator.tlsConfig.webhookTLSSecretRef.name=missing-ske-operator-webhook-tls
  [ "$status" -ne 0 ]
  [[ "$output" == *'Secret "missing-ske-operator-webhook-tls" was not found in namespace "kratix-platform-system"'* ]]
}

@test "certManager disabled: both TLS secrets rendered when no secretRefs set" {
  run helm_ske_operator \
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

@test "certManager disabled + webhookTLSSecretRef: webhook secret not created, deployment-config uses given name" {
  run helm_ske_operator \
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
  cert_secret_name=$(ske_deployment_config "$output" | yq '.spec.tlsConfig.certSecretName')
  [[ "$cert_secret_name" == "my-webhook-tls-secret" ]]
}

@test "certManager disabled + metricsServerTLSSecretRef: metrics secret not created, deployment-config uses given name" {
  run helm_ske_operator \
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
  metrics_cert_secret_name=$(ske_deployment_config "$output" | yq '.spec.tlsConfig.metricsServerCertSecretName')
  [[ "$metrics_cert_secret_name" == "my-metrics-tls-secret" ]]
}

@test "certManager disabled + both secretRefs: neither TLS secret created, deployment-config uses given names" {
  run helm_ske_operator \
    --set skeDeployment.tlsConfig.certManager.disabled=true \
    --set skeDeployment.tlsConfig.webhookTLSSecretRef.name=my-webhook-tls-secret \
    --set skeDeployment.tlsConfig.metricsServerTLSSecretRef.name=my-metrics-tls-secret
  [ "$status" -eq 0 ]

  local tls_secrets
  tls_secrets=$(printf '%s\n' "$output" | yq 'select(.kind == "Secret") | .metadata.name')
  [[ "$tls_secrets" != *"my-webhook-tls-secret"* ]]
  [[ "$tls_secrets" != *"my-metrics-tls-secret"* ]]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.tlsConfig.certSecretName') == "my-webhook-tls-secret" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.tlsConfig.metricsServerCertSecretName') == "my-metrics-tls-secret" ]]
}
