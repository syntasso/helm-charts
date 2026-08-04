#!/usr/bin/env bats

load helpers

@test "featureFlags: not rendered by default" {
  run helm_ske_operator
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.featureFlags') == "null" ]]
}

@test "featureFlags: dryRun rendered when set" {
  run helm_ske_operator \
    --set 'skeDeployment.featureFlags.dryRun=true'
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.featureFlags.dryRun') == "true" ]]
}

@test "featureFlags: passed through verbatim so new flags need no chart change" {
  run helm_ske_operator \
    --set 'skeDeployment.featureFlags.dryRun=false' \
    --set 'skeDeployment.featureFlags.someFutureFlag=true'
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.featureFlags.dryRun') == "false" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.featureFlags.someFutureFlag') == "true" ]]
}
