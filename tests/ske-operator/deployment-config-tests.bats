#!/usr/bin/env bats

load helpers

@test "deploymentConfig.resources rendered, nodeSelector/tolerations/affinity/volumes/volumeMounts absent" {
  run helm_ske_operator
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.resources.limits.memory') == "256Mi" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.nodeSelector') == "null" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.tolerations') == "null" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.affinity') == "null" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.volumes') == "null" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.volumeMounts') == "null" ]]
}

@test "deploymentConfig: not rendered when no fields are set" {
  run helm_ske_operator \
    --set 'skeDeployment.deploymentConfig.resources=null'
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig') == "null" ]]
}

@test "nodeSelector: rendered under deploymentConfig when set" {
  run helm_ske_operator \
    --set 'skeDeployment.deploymentConfig.nodeSelector.kubernetes\.io/os=linux'
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.nodeSelector["kubernetes.io/os"]') == "linux" ]]
}

@test "tolerations: rendered under deploymentConfig when set" {
  run helm_ske_operator \
    --set 'skeDeployment.deploymentConfig.tolerations[0].key=dedicated' \
    --set 'skeDeployment.deploymentConfig.tolerations[0].value=ske' \
    --set 'skeDeployment.deploymentConfig.tolerations[0].operator=Equal' \
    --set 'skeDeployment.deploymentConfig.tolerations[0].effect=NoSchedule'
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.tolerations[0].key') == "dedicated" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.tolerations[0].value') == "ske" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.tolerations[0].effect') == "NoSchedule" ]]
}

@test "affinity: rendered under deploymentConfig when set" {
  run helm_ske_operator \
    --set 'skeDeployment.deploymentConfig.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key=kubernetes.io/arch' \
    --set 'skeDeployment.deploymentConfig.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator=In' \
    --set 'skeDeployment.deploymentConfig.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[0]=amd64'
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  local match_expr
  match_expr='.spec.deploymentConfig.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0]'

  [[ $(printf '%s\n' "$deployment_config" | yq "${match_expr}.key") == "kubernetes.io/arch" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq "${match_expr}.operator") == "In" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq "${match_expr}.values[0]") == "amd64" ]]
}

@test "volumes: rendered under deploymentConfig when set" {
  run helm_ske_operator \
    --set 'skeDeployment.deploymentConfig.volumes[0].name=plugins' \
    --set 'skeDeployment.deploymentConfig.volumes[0].emptyDir.sizeLimit=1Gi'
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.volumes[0].name') == "plugins" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.volumes[0].emptyDir.sizeLimit') == "1Gi" ]]
}

@test "volumeMounts: rendered under deploymentConfig when set" {
  run helm_ske_operator \
    --set 'skeDeployment.deploymentConfig.volumeMounts[0].mountPath=/usr/local/libexec/vault' \
    --set 'skeDeployment.deploymentConfig.volumeMounts[0].name=plugins' \
    --set 'skeDeployment.deploymentConfig.volumeMounts[0].readOnly=true'
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.volumeMounts[0].mountPath') == "/usr/local/libexec/vault" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.volumeMounts[0].name') == "plugins" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.volumeMounts[0].readOnly') == "true" ]]
}

@test "all deploymentConfig keys: rendered together when set" {
  run helm_ske_operator \
    --set 'skeDeployment.deploymentConfig.nodeSelector.kubernetes\.io/os=linux' \
    --set 'skeDeployment.deploymentConfig.tolerations[0].key=dedicated' \
    --set 'skeDeployment.deploymentConfig.tolerations[0].value=ske' \
    --set 'skeDeployment.deploymentConfig.tolerations[0].operator=Equal' \
    --set 'skeDeployment.deploymentConfig.tolerations[0].effect=NoSchedule' \
    --set 'skeDeployment.deploymentConfig.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key=kubernetes.io/arch' \
    --set 'skeDeployment.deploymentConfig.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator=In' \
    --set 'skeDeployment.deploymentConfig.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[0]=amd64' \
    --set 'skeDeployment.deploymentConfig.volumes[0].name=plugins' \
    --set 'skeDeployment.deploymentConfig.volumes[0].emptyDir.sizeLimit=1Gi' \
    --set 'skeDeployment.deploymentConfig.volumeMounts[0].mountPath=/usr/local/libexec/vault' \
    --set 'skeDeployment.deploymentConfig.volumeMounts[0].name=plugins' \
    --set 'skeDeployment.deploymentConfig.volumeMounts[0].readOnly=true'
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.resources.limits.memory') == "256Mi" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.nodeSelector["kubernetes.io/os"]') == "linux" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.tolerations[0].key') == "dedicated" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key') == "kubernetes.io/arch" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.volumes[0].name') == "plugins" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.volumeMounts[0].mountPath') == "/usr/local/libexec/vault" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.volumeMounts[0].name') == "plugins" ]]
}
