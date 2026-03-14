#!/usr/bin/env bash

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../../scripts/external-input-flake.sh
. "$repo_root/scripts/external-input-flake.sh"

_nix_with_wrapper() {
  local cmd="$1"
  shift

  local wrapper_dir
  wrapper_dir=$(mk_wrapper_flake) || return 1

  local args=()
  local arg
  for arg in "$@"; do
    case "$arg" in
      .#*) args+=("path:$wrapper_dir#${arg#.#}") ;;
      *) args+=("$arg") ;;
    esac
  done

  nix --extra-experimental-features 'nix-command flakes' "$cmd" \
    --no-write-lock-file \
    "${args[@]}"
}

nix_generated_eval() {
  _nix_with_wrapper eval "$@"
}

nix_generated_build() {
  _nix_with_wrapper build "$@"
}

nix_generated_run() {
  _nix_with_wrapper run "$@"
}
