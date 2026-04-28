#!/usr/bin/env bats

load helpers

@test "releaseStorage.releasesPath: renders releasesPath in config" {
  run helm_ske_operator \
    --set-string releaseStorage.releasesPath=platform-releases
  [ "$status" -eq 0 ]

  local config
  config="$(ske_operator_config "$output")"

  [[ $(printf '%s\n' "$config" | yq '.releaseStorage.releasesPath') == "platform-releases" ]]
  [[ $(printf '%s\n' "$config" | yq '.releaseStorage.path') == "null" ]]
}

@test "releaseStorage.path: legacy key still renders in config" {
  run helm_ske_operator \
    --set-string releaseStorage.releasesPath= \
    --set-string releaseStorage.path=legacy-path
  [ "$status" -eq 0 ]

  local config
  config="$(ske_operator_config "$output")"

  [[ $(printf '%s\n' "$config" | yq '.releaseStorage.path') == "legacy-path" ]]
  [[ $(printf '%s\n' "$config" | yq '.releaseStorage.releasesPath') == "null" ]]
}

@test "releaseStorage.path and releaseStorage.releasesPath set together: helm template fails" {
  run helm_ske_operator \
    --set-string releaseStorage.path=legacy-path \
    --set-string releaseStorage.releasesPath=new-path

  [ "$status" -ne 0 ]
  [[ "$output" == *"releaseStorage.path and releaseStorage.releasesPath are mutually exclusive"* ]]
}
