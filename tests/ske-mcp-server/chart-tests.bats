#!/usr/bin/env bats

setup_file() {
  export REPO_ROOT CHART
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  CHART="$REPO_ROOT/ske-mcp-server"
  command -v helm >/dev/null || { echo "helm not found"; exit 1; }
  command -v yq >/dev/null || { echo "yq not found"; exit 1; }
}

@test "ske-mcp-server chart lints with a chart-managed token" {
  run helm lint "$CHART" --set-string auth.token=test-token

  [ "$status" -eq 0 ]
}

@test "ske-mcp-server renders a secure single-pod deployment in the release namespace" {
  run helm template platform-mcp "$CHART" \
    --namespace platform-system \
    --set-string auth.token=test-token

  [ "$status" -eq 0 ]
  local deployment
  deployment="$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment")')"
  [ "$(printf '%s\n' "$deployment" | yq '.metadata.name')" = "platform-mcp-ske-mcp-server" ]
  [ "$(printf '%s\n' "$deployment" | yq '.metadata.namespace')" = "platform-system" ]
  [ "$(printf '%s\n' "$deployment" | yq '.spec.replicas')" = "1" ]
  [ "$(printf '%s\n' "$deployment" | yq '.spec.strategy.type')" = "Recreate" ]
  [ "$(printf '%s\n' "$deployment" | yq '.spec.template.spec.containers[0].image')" = "ghcr.io/syntasso/ske-mcp-server:v0.2.2" ]
  [ "$(printf '%s\n' "$deployment" | yq '.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem')" = "true" ]
  [ "$(printf '%s\n' "$deployment" | yq '.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation')" = "false" ]
  [ "$(printf '%s\n' "$deployment" | yq '.spec.template.spec.containers[0].securityContext.runAsNonRoot')" = "true" ]
  [ "$(printf '%s\n' "$deployment" | yq '.spec.template.spec.containers[0].securityContext.runAsUser')" = "65532" ]
  [ "$(printf '%s\n' "$deployment" | yq '.spec.template.spec.containers[0].securityContext.runAsGroup')" = "65532" ]
  [ "$(printf '%s\n' "$deployment" | yq '.spec.template.spec.containers[0].securityContext.capabilities.drop[0]')" = "ALL" ]
  [ "$(printf '%s\n' "$deployment" | yq '.spec.template.spec.securityContext.seccompProfile.type')" = "RuntimeDefault" ]
  [ "$(printf '%s\n' "$deployment" | yq '.spec.template.spec.containers[0].startupProbe.httpGet.path')" = "/healthz" ]
  [ "$(printf '%s\n' "$deployment" | yq '.spec.template.spec.containers[0].livenessProbe.httpGet.path')" = "/healthz" ]
  [ "$(printf '%s\n' "$deployment" | yq '.spec.template.spec.containers[0].readinessProbe.httpGet.path')" = "/readyz" ]
  [ "$(printf '%s\n' "$deployment" | yq '.spec.template.spec.containers[0].resources.requests.cpu')" = "10m" ]
  [ "$(printf '%s\n' "$deployment" | yq '.spec.template.spec.containers[0].resources.requests.memory')" = "32Mi" ]
  [ "$(printf '%s\n' "$deployment" | yq '.spec.template.spec.containers[0].resources.limits.memory')" = "128Mi" ]

  local service wildcard_rules
  service="$(printf '%s\n' "$output" | yq 'select(.kind == "Service")')"
  wildcard_rules="$(printf '%s\n' "$output" | yq 'select(.kind == "ClusterRole") | .rules[] | select(.apiGroups[0] == "*" and .resources[0] == "*") | .verbs[0]')"
  [ "$(printf '%s\n' "$service" | yq '.spec.ports[0].port')" = "80" ]
  [ "$(printf '%s\n' "$service" | yq '.spec.ports[0].targetPort')" = "http" ]
  [[ "$wildcard_rules" == *"list"* ]]
  [[ "$wildcard_rules" == *"create"* ]]
}

@test "ske-mcp-server keeps selector labels authoritative and supports full probe settings" {
  run helm template custom "$CHART" \
    --set-string auth.token=test-token \
    --set-string 'podLabels.app\.kubernetes\.io/name=unsafe-override' \
    --set-string 'podLabels.example\.com/team=platform' \
    --set startupProbe.initialDelaySeconds=5

  [ "$status" -eq 0 ]
  local deployment selector_name pod_name
  deployment="$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment")')"
  selector_name="$(printf '%s\n' "$deployment" | yq '.spec.selector.matchLabels."app.kubernetes.io/name"')"
  pod_name="$(printf '%s\n' "$deployment" | yq '.spec.template.metadata.labels."app.kubernetes.io/name"')"
  [ "$selector_name" = "ske-mcp-server" ]
  [ "$pod_name" = "$selector_name" ]
  [ "$(printf '%s\n' "$deployment" | yq '.spec.template.metadata.labels."example.com/team"')" = "platform" ]
  [ "$(printf '%s\n' "$deployment" | yq '.spec.template.spec.containers[0].startupProbe.initialDelaySeconds')" = "5" ]
}

@test "ske-mcp-server can reference an externally managed auth secret" {
  run helm template test "$CHART" \
    --set auth.existingSecret.name=external-auth \
    --set auth.existingSecret.key=bearer-token

  [ "$status" -eq 0 ]
  local secrets token_env
  secrets="$(printf '%s\n' "$output" | yq 'select(.kind == "Secret") | .metadata.name')"
  token_env="$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment") | .spec.template.spec.containers[0].env[] | select(.name == "MCP_AUTH_TOKEN")')"
  [ -z "$secrets" ]
  [ "$(printf '%s\n' "$token_env" | yq '.valueFrom.secretKeyRef.name')" = "external-auth" ]
  [ "$(printf '%s\n' "$token_env" | yq '.valueFrom.secretKeyRef.key')" = "bearer-token" ]
}

@test "ske-mcp-server rejects missing or conflicting auth configuration" {
  run helm template test "$CHART"
  [ "$status" -ne 0 ]
  [[ "$output" == *"exactly one"* ]]

  run helm template test "$CHART" \
    --set-string auth.token=test-token \
    --set auth.existingSecret.name=external-auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"exactly one"* ]]
}

@test "ske-mcp-server rejects multiple replicas" {
  run helm template test "$CHART" \
    --set-string auth.token=test-token \
    --set replicaCount=2

  [ "$status" -ne 0 ]
  [[ "$output" == *"replicaCount"* ]]
}

@test "ske-mcp-server supports externally managed RBAC and service account" {
  run helm template test "$CHART" \
    --set-string auth.token=test-token \
    --set rbac.create=false \
    --set serviceAccount.create=false \
    --set serviceAccount.name=platform-mcp

  [ "$status" -eq 0 ]
  local cluster_resources service_account
  cluster_resources="$(printf '%s\n' "$output" | yq 'select(.kind == "ClusterRole" or .kind == "ClusterRoleBinding") | .kind')"
  service_account="$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment") | .spec.template.spec.serviceAccountName')"
  [ -z "$cluster_resources" ]
  [ "$service_account" = "platform-mcp" ]
}

@test "ske-mcp-server ingress exposes only mcp and requires TLS" {
  run helm template test "$CHART" \
    --set-string auth.token=test-token \
    --set ingress.enabled=true \
    --set ingress.className=nginx \
    --set ingress.host=mcp.example.com \
    --set ingress.tls.secretName=mcp-tls

  [ "$status" -eq 0 ]
  local ingress
  ingress="$(printf '%s\n' "$output" | yq 'select(.kind == "Ingress")')"
  [ "$(printf '%s\n' "$ingress" | yq '.spec.rules[0].http.paths[0].path')" = "/mcp" ]
  [ "$(printf '%s\n' "$ingress" | yq '.spec.rules[0].http.paths[0].pathType')" = "Exact" ]
  [ "$(printf '%s\n' "$ingress" | yq '.spec.tls[0].secretName')" = "mcp-tls" ]

  run helm template test "$CHART" \
    --set-string auth.token=test-token \
    --set ingress.enabled=true \
    --set ingress.host=mcp.example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"TLS"* ]]
}

@test "ske-mcp-server supports immutable image selection" {
  run helm template test "$CHART" \
    --set-string auth.token=test-token \
    --set image.repository=registry.example.com/platform/mcp \
    --set image.tag=canary \
    --set imagePullSecrets[0].name=registry-auth

  [ "$status" -eq 0 ]
  local tagged_image pull_secret
  tagged_image="$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment") | .spec.template.spec.containers[0].image')"
  pull_secret="$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment") | .spec.template.spec.imagePullSecrets[0].name')"
  [ "$tagged_image" = "registry.example.com/platform/mcp:canary" ]
  [ "$pull_secret" = "registry-auth" ]

  run helm template test "$CHART" \
    --set-string auth.token=test-token \
    --set image.repository=registry.example.com/platform/mcp \
    --set image.tag=canary \
    --set image.digest=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

  [ "$status" -eq 0 ]
  local image
  image="$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment") | .spec.template.spec.containers[0].image')"
  [ "$image" = "registry.example.com/platform/mcp@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" ]
}
