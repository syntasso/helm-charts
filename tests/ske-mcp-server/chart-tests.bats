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

  local service
  service="$(printf '%s\n' "$output" | yq 'select(.kind == "Service")')"
  [ "$(printf '%s\n' "$service" | yq '.spec.ports[0].port')" = "80" ]
  [ "$(printf '%s\n' "$service" | yq '.spec.ports[0].targetPort')" = "http" ]
}

@test "ske-mcp-server grants no wildcard and cannot read secrets by default" {
  # The assertion this chart most needs. `apiGroups: ["*"]` also matches the core group, and `list`
  # on core secrets returns their values — so a wildcard makes the ServiceAccount a cluster-wide
  # credential reader. RBAC has no exception to walk that back.
  run helm template test "$CHART" --set-string auth.token=test-token

  [ "$status" -eq 0 ]
  # Matched as whole lines with grep rather than inside yq: `select(.apiGroups[] == "*")` emits the
  # rule regardless of the comparison's result, so it silently passes.
  local wildcard_groups wildcard_resources core_resources
  wildcard_groups="$(printf '%s\n' "$output" | yq 'select(.kind == "ClusterRole") | .rules[].apiGroups[]' | grep -Fx '*' || true)"
  wildcard_resources="$(printf '%s\n' "$output" | yq 'select(.kind == "ClusterRole") | .rules[].resources[]' | grep -Fx '*' || true)"
  core_resources="$(printf '%s\n' "$output" | yq 'select(.kind == "ClusterRole") | .rules[] | select(.apiGroups[0] == "") | .resources[]' | sort | tr '\n' ' ')"

  [ -z "$wildcard_groups" ]
  [ -z "$wildcard_resources" ]
  # Namespaces and events only. Anything else in the core group is a finding, secrets above all.
  [ "$core_resources" = "events namespaces " ]
}

@test "ske-mcp-server grants promise request access per API group, never by wildcard group" {
  run helm template test "$CHART" \
    --set-string auth.token=test-token \
    --set 'rbac.requestApiGroups[0]=testing.kratix.io' \
    --set 'rbac.requestApiGroups[1]=lre.kratix.io'

  [ "$status" -eq 0 ]
  local rule core_resources
  rule="$(printf '%s\n' "$output" | yq 'select(.kind == "ClusterRole") | .rules[] | select(.resources[0] == "*")')"
  core_resources="$(printf '%s\n' "$output" | yq 'select(.kind == "ClusterRole") | .rules[] | select(.apiGroups[0] == "") | .resources[]' | sort | tr '\n' ' ')"

  [ "$(printf '%s\n' "$rule" | yq '.apiGroups | length')" = "2" ]
  [ "$(printf '%s\n' "$rule" | yq '.apiGroups[0]')" = "testing.kratix.io" ]
  [ "$(printf '%s\n' "$rule" | yq '.verbs | sort | join(",")')" = "create,list" ]
  # `resources: ["*"]` is only safe because the groups above hold nothing but Promise-defined CRs.
  # The core group must be untouched by the allowlist.
  [ "$core_resources" = "events namespaces " ]
}

@test "ske-mcp-server refuses a wildcard API group" {
  run helm template test "$CHART" \
    --set-string auth.token=test-token \
    --set 'rbac.requestApiGroups[0]=*'

  [ "$status" -ne 0 ]
  [[ "$output" == *"requestApiGroups"* ]]
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

@test "ske-mcp-server rejects malformed probes before rendering" {
  run helm template test "$CHART" \
    --set-string auth.token=test-token \
    --set-string startupProbe.periodSeconds=invalid
  [ "$status" -ne 0 ]
  [[ "$output" == *"startupProbe"* ]]
  [[ "$output" == *"periodSeconds"* ]]
  [[ "$output" == *"integer"* ]]
  [[ "$output" == *"string"* ]]

  run helm template test "$CHART" \
    --set-string auth.token=test-token \
    --set startupProbe.httpGet=null
  [ "$status" -ne 0 ]
  [[ "$output" == *"startupProbe"* ]]
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

@test "ske-mcp-server refuses to render an unauthenticated endpoint" {
  # With no mechanism configured the server registers no bearer-token middleware on /mcp, so it
  # answers unauthenticated callers. Failing to render is the only way that does not reach a
  # cluster quietly.
  run helm template test "$CHART"
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least one mechanism"* ]]
  [[ "$output" == *"no authentication"* ]]
}

@test "ske-mcp-server rejects conflicting static token configuration" {
  run helm template test "$CHART" \
    --set-string auth.token=test-token \
    --set auth.existingSecret.name=external-auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"exactly one"* ]]
}

@test "ske-mcp-server requires the OIDC issuer and resource URL together" {
  # The resource URL is the audience the server demands in every token. With the issuer alone the
  # server refuses to start, so failing here turns a CrashLoopBackOff into a render error.
  run helm template test "$CHART" --set auth.oidc.issuer=https://keycloak.example.com/realms/mcp
  [ "$status" -ne 0 ]
  [[ "$output" == *"auth.oidc.resourceURL"* ]]

  run helm template test "$CHART" --set auth.oidc.resourceURL=https://mcp.example.com/mcp
  [ "$status" -ne 0 ]
  [[ "$output" == *"auth.oidc.issuer"* ]]
}

@test "ske-mcp-server configures OIDC without a static token" {
  run helm template test "$CHART" \
    --set auth.oidc.issuer=https://keycloak.example.com/realms/mcp \
    --set auth.oidc.resourceURL=https://mcp.example.com/mcp \
    --set auth.oidc.subjectClaim=preferred_username

  [ "$status" -eq 0 ]
  # One yq pass per lookup: piping a stream of env entries into a second yq re-parses them as a
  # single document, which silently matches nothing.
  local names
  names="$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment") | .spec.template.spec.containers[0].env[].name' | tr '\n' ' ')"

  [ "$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment") | .spec.template.spec.containers[0].env[] | select(.name == "OIDC_ISSUER") | .value')" = "https://keycloak.example.com/realms/mcp" ]
  [ "$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment") | .spec.template.spec.containers[0].env[] | select(.name == "MCP_RESOURCE_URL") | .value')" = "https://mcp.example.com/mcp" ]
  [ "$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment") | .spec.template.spec.containers[0].env[] | select(.name == "OIDC_SUBJECT_CLAIM") | .value')" = "preferred_username" ]
  # No token means no MCP_AUTH_TOKEN and no chart-managed Secret at all.
  [[ "$names" != *"MCP_AUTH_TOKEN"* ]]
  [ -z "$(printf '%s\n' "$output" | yq 'select(.kind == "Secret") | .metadata.name')" ]
  # Unset optional overrides must not render as empty env vars, which the server would reject.
  [[ "$names" != *"OIDC_JWKS_URI"* ]]
  [[ "$names" != *"OIDC_CLOCK_SKEW"* ]]
}

@test "ske-mcp-server supports OIDC and a static token together" {
  # The two are not exclusive: an installation can carry a legacy token while callers migrate.
  run helm template test "$CHART" \
    --set-string auth.token=test-token \
    --set auth.oidc.issuer=https://keycloak.example.com/realms/mcp \
    --set auth.oidc.resourceURL=https://mcp.example.com/mcp

  [ "$status" -eq 0 ]
  local names
  names="$(printf '%s\n' "$output" | yq 'select(.kind == "Deployment") | .spec.template.spec.containers[0].env[] | .name' | tr '\n' ' ')"
  [[ "$names" == *"MCP_AUTH_TOKEN"* ]]
  [[ "$names" == *"OIDC_ISSUER"* ]]
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

@test "ske-mcp-server ingress exposes only mcp with a static token" {
  run helm template test "$CHART" \
    --set-string auth.token=test-token \
    --set ingress.enabled=true \
    --set ingress.className=nginx \
    --set ingress.host=mcp.example.com \
    --set ingress.tls.secretName=mcp-tls

  [ "$status" -eq 0 ]
  local ingress paths
  ingress="$(printf '%s\n' "$output" | yq 'select(.kind == "Ingress")')"
  paths="$(printf '%s\n' "$ingress" | yq '.spec.rules[0].http.paths[].path' | tr '\n' ' ')"
  [ "$(printf '%s\n' "$ingress" | yq '.spec.rules[0].http.paths[0].pathType')" = "Exact" ]
  [ "$(printf '%s\n' "$ingress" | yq '.spec.tls[0].secretName')" = "mcp-tls" ]
  # No OIDC means the server registers no metadata handlers, so routing them would be a 404.
  [ "$paths" = "/mcp " ]
}

@test "ske-mcp-server ingress routes the OIDC discovery documents" {
  # An MCP client fetches RFC 9728 protected-resource metadata to find the authorization server.
  # Routing only /mcp leaves both paths 404 through the ingress, so the client cannot start the
  # flow even though the server answers correctly behind it.
  run helm template test "$CHART" \
    --set auth.oidc.issuer=https://keycloak.example.com/realms/mcp \
    --set auth.oidc.resourceURL=https://mcp.example.com/mcp \
    --set ingress.enabled=true \
    --set ingress.className=nginx \
    --set ingress.host=mcp.example.com \
    --set ingress.tls.secretName=mcp-tls

  [ "$status" -eq 0 ]
  local paths
  paths="$(printf '%s\n' "$output" | yq 'select(.kind == "Ingress") | .spec.rules[0].http.paths[].path' | tr '\n' ' ')"
  [ "$paths" = "/mcp /.well-known/oauth-protected-resource /.well-known/oauth-protected-resource/mcp " ]
}

@test "ske-mcp-server ingress omits tls where it terminates upstream" {
  # A load balancer holding its own certificate — ACM on an AWS ALB, say — has no TLS Secret to
  # name. Requiring one made the chart impossible to install there, and rendering `secretName: ""`
  # names a Secret that cannot exist.
  run helm template test "$CHART" \
    --set-string auth.token=test-token \
    --set ingress.enabled=true \
    --set ingress.className=alb \
    --set ingress.host=mcp.example.com

  [ "$status" -eq 0 ]
  local ingress
  ingress="$(printf '%s\n' "$output" | yq 'select(.kind == "Ingress")')"
  [ "$(printf '%s\n' "$ingress" | yq '.spec.tls')" = "null" ]
  [ "$(printf '%s\n' "$ingress" | yq '.spec.rules[0].host')" = "mcp.example.com" ]
}

@test "ske-mcp-server still requires an ingress host" {
  run helm template test "$CHART" \
    --set-string auth.token=test-token \
    --set ingress.enabled=true
  [ "$status" -ne 0 ]
  [[ "$output" == *"ingress.host"* ]]
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
