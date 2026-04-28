#!/usr/bin/env bash
# Shared helpers for ske-operator bats tests.
# Load in each test file with: load helpers

setup_file() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  command -v helm >/dev/null || { echo "helm not found"; exit 1; }
  command -v yq >/dev/null || { echo "yq not found"; exit 1; }
}

# Runs helm template for the ske-operator chart.
# Usage: run helm_ske_operator [--set key=value ...]
helm_ske_operator() {
  helm template test "$REPO_ROOT/ske-operator" "$@"
}

# Extracts the ske-operator ConfigMap config as YAML from helm output.
# Usage: config="$(ske_operator_config "$output")"
ske_operator_config() {
  printf '%s\n' "$1" | yq 'select(.kind == "ConfigMap" and .metadata.name == "ske-operator").data.config'
}

# Extracts the ske-deployment ConfigMap config as YAML from helm output.
# Usage: config="$(ske_deployment_config "$output")"
ske_deployment_config() {
  printf '%s\n' "$1" | yq 'select(.kind == "ConfigMap" and .metadata.name == "ske-deployment-config") | .data["ske-deployment"]'
}
