#!/usr/bin/env bats

load helpers

@test "webhookConfig: not rendered by default" {
  run helm_ske_operator
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.webhookConfig') == "null" ]]
}

@test "webhookConfig: timeoutSeconds rendered with override value" {
  run helm_ske_operator \
    --set 'skeDeployment.webhookConfig.timeoutSeconds=5'
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.webhookConfig.timeoutSeconds') == "5" ]]
}
