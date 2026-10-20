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

@test "platformManagerDeploymentConfig.resources rendered, nodeSelector/tolerations/affinity/volumes/volumeMounts absent" {
  run helm_ske_operator
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.resources.limits.memory') == "128Mi" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.resources.limits.cpu') == "200m" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.nodeSelector') == "null" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.tolerations') == "null" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.affinity') == "null" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.volumes') == "null" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.volumeMounts') == "null" ]]
}

@test "platformManagerDeploymentConfig: not rendered when no fields are set" {
  run helm_ske_operator \
    --set 'skeDeployment.platformManagerDeploymentConfig.resources=null'
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig') == "null" ]]
}

@test "nodeSelector: rendered under platformManagerDeploymentConfig when set" {
  run helm_ske_operator \
    --set 'skeDeployment.platformManagerDeploymentConfig.nodeSelector.kubernetes\.io/os=linux'
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.nodeSelector["kubernetes.io/os"]') == "linux" ]]
}

@test "tolerations: rendered under platformManagerDeploymentConfig when set" {
  run helm_ske_operator \
    --set 'skeDeployment.platformManagerDeploymentConfig.tolerations[0].key=dedicated' \
    --set 'skeDeployment.platformManagerDeploymentConfig.tolerations[0].value=ske' \
    --set 'skeDeployment.platformManagerDeploymentConfig.tolerations[0].operator=Equal' \
    --set 'skeDeployment.platformManagerDeploymentConfig.tolerations[0].effect=NoSchedule'
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.tolerations[0].key') == "dedicated" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.tolerations[0].value') == "ske" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.tolerations[0].effect') == "NoSchedule" ]]
}

@test "affinity: rendered under platformManagerDeploymentConfig when set" {
  run helm_ske_operator \
    --set 'skeDeployment.platformManagerDeploymentConfig.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key=kubernetes.io/arch' \
    --set 'skeDeployment.platformManagerDeploymentConfig.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator=In' \
    --set 'skeDeployment.platformManagerDeploymentConfig.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[0]=amd64'
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  local match_expr
  match_expr='.spec.platformManagerDeploymentConfig.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0]'

  [[ $(printf '%s\n' "$deployment_config" | yq "${match_expr}.key") == "kubernetes.io/arch" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq "${match_expr}.operator") == "In" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq "${match_expr}.values[0]") == "amd64" ]]
}

@test "volumes: rendered under platformManagerDeploymentConfig when set" {
  run helm_ske_operator \
    --set 'skeDeployment.platformManagerDeploymentConfig.volumes[0].name=plugins' \
    --set 'skeDeployment.platformManagerDeploymentConfig.volumes[0].emptyDir.sizeLimit=1Gi'
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.volumes[0].name') == "plugins" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.volumes[0].emptyDir.sizeLimit') == "1Gi" ]]
}

@test "volumeMounts: rendered under platformManagerDeploymentConfig when set" {
  run helm_ske_operator \
    --set 'skeDeployment.platformManagerDeploymentConfig.volumeMounts[0].mountPath=/usr/local/libexec/vault' \
    --set 'skeDeployment.platformManagerDeploymentConfig.volumeMounts[0].name=plugins' \
    --set 'skeDeployment.platformManagerDeploymentConfig.volumeMounts[0].readOnly=true'
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.volumeMounts[0].mountPath') == "/usr/local/libexec/vault" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.volumeMounts[0].name') == "plugins" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.volumeMounts[0].readOnly') == "true" ]]
}

@test "all platformManagerDeploymentConfig keys: rendered together when set" {
  run helm_ske_operator \
    --set 'skeDeployment.platformManagerDeploymentConfig.nodeSelector.kubernetes\.io/os=linux' \
    --set 'skeDeployment.platformManagerDeploymentConfig.tolerations[0].key=dedicated' \
    --set 'skeDeployment.platformManagerDeploymentConfig.tolerations[0].value=ske' \
    --set 'skeDeployment.platformManagerDeploymentConfig.tolerations[0].operator=Equal' \
    --set 'skeDeployment.platformManagerDeploymentConfig.tolerations[0].effect=NoSchedule' \
    --set 'skeDeployment.platformManagerDeploymentConfig.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key=kubernetes.io/arch' \
    --set 'skeDeployment.platformManagerDeploymentConfig.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator=In' \
    --set 'skeDeployment.platformManagerDeploymentConfig.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[0]=amd64' \
    --set 'skeDeployment.platformManagerDeploymentConfig.volumes[0].name=plugins' \
    --set 'skeDeployment.platformManagerDeploymentConfig.volumes[0].emptyDir.sizeLimit=1Gi' \
    --set 'skeDeployment.platformManagerDeploymentConfig.volumeMounts[0].mountPath=/usr/local/libexec/vault' \
    --set 'skeDeployment.platformManagerDeploymentConfig.volumeMounts[0].name=plugins' \
    --set 'skeDeployment.platformManagerDeploymentConfig.volumeMounts[0].readOnly=true'
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.resources.limits.memory') == "128Mi" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.nodeSelector["kubernetes.io/os"]') == "linux" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.tolerations[0].key') == "dedicated" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key') == "kubernetes.io/arch" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.volumes[0].name') == "plugins" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.volumeMounts[0].mountPath') == "/usr/local/libexec/vault" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.volumeMounts[0].name') == "plugins" ]]
}

@test "replicas and topologySpreadConstraints: absent from both deployment configs by default" {
  run helm_ske_operator
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig | has("replicas")') == "false" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig | has("topologySpreadConstraints")') == "false" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig | has("replicas")') == "false" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig | has("topologySpreadConstraints")') == "false" ]]
}

@test "replicas: rendered under deploymentConfig and platformManagerDeploymentConfig when set" {
  run helm_ske_operator \
    --set 'skeDeployment.deploymentConfig.replicas=2' \
    --set 'skeDeployment.platformManagerDeploymentConfig.replicas=3'
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.replicas') == "2" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.platformManagerDeploymentConfig.replicas') == "3" ]]
}

@test "replicas: 0 is passed through so the Kratix CRD rejects it, not silently dropped" {
  run helm_ske_operator \
    --set 'skeDeployment.deploymentConfig.replicas=0'
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  [[ $(printf '%s\n' "$deployment_config" | yq '.spec.deploymentConfig.replicas') == "0" ]]
}

@test "topologySpreadConstraints: rendered as written under both deployment configs" {
  run helm_ske_operator \
    --set 'skeDeployment.deploymentConfig.topologySpreadConstraints[0].maxSkew=1' \
    --set 'skeDeployment.deploymentConfig.topologySpreadConstraints[0].topologyKey=kubernetes.io/hostname' \
    --set 'skeDeployment.deploymentConfig.topologySpreadConstraints[0].whenUnsatisfiable=DoNotSchedule' \
    --set 'skeDeployment.deploymentConfig.topologySpreadConstraints[0].nodeTaintsPolicy=Honor' \
    --set 'skeDeployment.deploymentConfig.topologySpreadConstraints[0].matchLabelKeys[0]=pod-template-hash' \
    --set 'skeDeployment.deploymentConfig.topologySpreadConstraints[0].labelSelector.matchLabels.app\.kubernetes\.io/component=kratix-manager' \
    --set 'skeDeployment.platformManagerDeploymentConfig.topologySpreadConstraints[0].maxSkew=1' \
    --set 'skeDeployment.platformManagerDeploymentConfig.topologySpreadConstraints[0].topologyKey=topology.kubernetes.io/zone' \
    --set 'skeDeployment.platformManagerDeploymentConfig.topologySpreadConstraints[0].whenUnsatisfiable=ScheduleAnyway'
  [ "$status" -eq 0 ]

  local deployment_config
  deployment_config="$(ske_deployment_config "$output")"

  local tsc='.spec.deploymentConfig.topologySpreadConstraints[0]'
  [[ $(printf '%s\n' "$deployment_config" | yq "${tsc}.maxSkew") == "1" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq "${tsc}.topologyKey") == "kubernetes.io/hostname" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq "${tsc}.whenUnsatisfiable") == "DoNotSchedule" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq "${tsc}.nodeTaintsPolicy") == "Honor" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq "${tsc}.matchLabelKeys[0]") == "pod-template-hash" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq "${tsc}.labelSelector.matchLabels[\"app.kubernetes.io/component\"]") == "kratix-manager" ]]

  local pm_tsc='.spec.platformManagerDeploymentConfig.topologySpreadConstraints[0]'
  [[ $(printf '%s\n' "$deployment_config" | yq "${pm_tsc}.topologyKey") == "topology.kubernetes.io/zone" ]]
  [[ $(printf '%s\n' "$deployment_config" | yq "${pm_tsc}.whenUnsatisfiable") == "ScheduleAnyway" ]]
}
