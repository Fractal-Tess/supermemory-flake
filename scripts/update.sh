#!/usr/bin/env bash
set -euo pipefail

readonly UPSTREAM_REPO="supermemoryai/supermemory"
readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required tool: $1"
}

github_api_get() {
  local url="$1"
  local -a args=(
    --silent
    --show-error
    --fail
    --location
    --header "Accept: application/vnd.github+json"
    --header "X-GitHub-Api-Version: 2022-11-28"
    --header "User-Agent: Fractal-Tess/supermemory-flake"
  )

  if [[ -n "${GH_TOKEN:-}" ]]; then
    args+=(--header "Authorization: Bearer ${GH_TOKEN}")
  fi

  curl "${args[@]}" "$url"
}

asset_digest() {
  local release_json="$1"
  local asset_name="$2"
  local digest

  digest="$(jq -r --arg name "$asset_name" '.assets[] | select(.name == $name) | .digest' <<<"$release_json")"
  [[ "$digest" == sha256:* ]] || fail "missing SHA-256 digest for ${asset_name}"
  printf '%s\n' "${digest#sha256:}"
}

to_sri() {
  nix hash convert --hash-algo sha256 --to sri "$1"
}

main() {
  local requested_version="${1:-}"
  local current_version release_json version x86_hash arm64_hash

  require_tool curl
  require_tool jq
  require_tool nix
  require_tool sed

  cd "$ROOT_DIR"
  current_version="$(sed -n 's/^  version = "\([^"]*\)";/\1/p' packages/supermemory-server.nix)"
  [[ -n "$current_version" ]] || fail "could not read the packaged version"

  # The repository also publishes SDK releases, so pick the newest stable
  # server-v* tag rather than GitHub's "latest".
  if [[ -n "$requested_version" ]]; then
    version="${requested_version#server-v}"
    release_json="$(github_api_get "https://api.github.com/repos/${UPSTREAM_REPO}/releases/tags/server-v${version}")"
  else
    release_json="$(github_api_get "https://api.github.com/repos/${UPSTREAM_REPO}/releases?per_page=100" \
      | jq '[.[] | select((.tag_name | startswith("server-v")) and (.draft or .prerelease | not))][0]')"
    version="$(jq -r '.tag_name | sub("^server-v"; "")' <<<"$release_json")"
  fi

  [[ -n "$version" && "$version" != "null" ]] || fail "could not determine the upstream version"
  [[ "$(jq -r '.draft or .prerelease' <<<"$release_json")" == "false" ]] || fail "server-v${version} is not a stable release"

  printf 'Current version: %s\nLatest version:  %s\n' "$current_version" "$version"
  if [[ "$current_version" == "$version" ]]; then
    printf 'Already up to date.\n'
    exit 0
  fi

  x86_hash="$(to_sri "$(asset_digest "$release_json" "supermemory-server-linux-x64")")"
  arm64_hash="$(to_sri "$(asset_digest "$release_json" "supermemory-server-linux-arm64")")"

  sed -i \
    -e "s|^  version = \"${current_version}\";|  version = \"${version}\";|" \
    -e "/x86_64-linux = {/,/};/ s|^      hash = .*|      hash = \"${x86_hash}\";|" \
    -e "/aarch64-linux = {/,/};/ s|^      hash = .*|      hash = \"${arm64_hash}\";|" \
    packages/supermemory-server.nix

  sed -i \
    -e "s|releases/tag/server-v${current_version}|releases/tag/server-v${version}|g" \
    -e "s|Supermemory_server-${current_version}|Supermemory_server-${version}|g" \
    -e "s|Supermemory server ${current_version}|Supermemory server ${version}|g" \
    -e "s|./scripts/update.sh ${current_version}|./scripts/update.sh ${version}|g" \
    -e "s|The ${current_version} server listens|The ${version} server listens|g" \
    README.md

  nix fmt packages/supermemory-server.nix
  nix flake check --print-build-logs
  nix build .#supermemory-server --print-build-logs
  test -x result/bin/supermemory-server || fail "built package does not contain bin/supermemory-server"

  printf 'Updated the Supermemory server from %s to %s.\n' "$current_version" "$version"
}

main "$@"
