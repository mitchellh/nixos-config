#!/usr/bin/env bash

_external_input_flake_script_dir=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)

canonicalize_dir() {
  (cd "$1" >/dev/null 2>&1 && pwd -P)
}

external_input_repo_root() {
  local repo_root="${NIX_CONFIG_DIR:-}"
  if [ -n "$repo_root" ]; then
    canonicalize_dir "$repo_root"
  else
    (cd "${_external_input_flake_script_dir}/.." >/dev/null 2>&1 && pwd)
  fi
}

generated_input_dir() {
  local dir="${GENERATED_INPUT_DIR:-}"
  if [ -z "$dir" ]; then
    if [ -d "$HOME/.local/share/nix-config-generated" ]; then
      dir="$HOME/.local/share/nix-config-generated"
    elif [ -d /nixos-generated ]; then
      dir=/nixos-generated
    else
      printf 'FAIL: generated dataset missing; set GENERATED_INPUT_DIR or create ~/.local/share/nix-config-generated (host) or /nixos-generated (VM)\n' >&2
      return 1
    fi
  fi

  if [ ! -d "$dir" ]; then
    printf 'FAIL: generated dataset directory does not exist: %s\n' "$dir" >&2
    return 1
  fi

  canonicalize_dir "$dir"
}

yeet_and_yoink_input_dir() {
  local dir="${YEET_AND_YOINK_INPUT_DIR:-}"
  if [ -z "$dir" ]; then
    if [ -d "$HOME/Projects/yeet-and-yoink" ]; then
      dir="$HOME/Projects/yeet-and-yoink"
    elif [ -d /Users/m/Projects/yeet-and-yoink ]; then
      dir=/Users/m/Projects/yeet-and-yoink
    else
      printf 'FAIL: yeet-and-yoink source missing; set YEET_AND_YOINK_INPUT_DIR or expose /Users/m/Projects/yeet-and-yoink\n' >&2
      return 1
    fi
  fi

  if [ ! -d "$dir" ]; then
    printf 'FAIL: yeet-and-yoink directory does not exist: %s\n' "$dir" >&2
    return 1
  fi

  canonicalize_dir "$dir"
}

mk_wrapper_flake() {
  if [ -n "${_nix_wrapper_dir:-}" ] && [ -f "${_nix_wrapper_dir}/flake.nix" ]; then
    printf '%s\n' "$_nix_wrapper_dir"
    return 0
  fi

  local generated_dir yeet_dir repo_root tmp_root wrapper_dir input_block output_args
  generated_dir=$(generated_input_dir) || return 1
  yeet_dir=""
  if ! yeet_dir=$(yeet_and_yoink_input_dir 2>/dev/null); then
    yeet_dir=""
  fi
  repo_root=$(external_input_repo_root) || return 1
  tmp_root="${TMPDIR:-/tmp}"
  wrapper_dir=$(mktemp -d "${tmp_root%/}/nix-wrapper-XXXXXX") || return 1
  wrapper_dir=$(cd "$wrapper_dir" >/dev/null 2>&1 && pwd -P) || return 1

  input_block=""
  output_args=""
  if [ -n "$yeet_dir" ]; then
    input_block=$(cat <<EOF
  inputs.yeetAndYoink = {
    url = "git+file://$yeet_dir?dir=plugins/zellij-break";
    flake = false;
  };
EOF
)
    output_args=$(cat <<'EOF'
      yeetAndYoink = inputs.yeetAndYoink;
EOF
)
  fi

  cat >"$wrapper_dir/flake.nix" <<EOF
{
  inputs.config.url = "path:$repo_root";
  inputs.generated = {
    url = "path:$generated_dir";
    flake = false;
  };
${input_block}
  outputs = { config, generated, ... }@inputs:
    config.lib.mkOutputs {
      inherit generated;
${output_args}    };
}
EOF

  _nix_wrapper_dir="$wrapper_dir"
  printf '%s\n' "$wrapper_dir"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  _nix_wrapper_dir=""
  mk_wrapper_flake
fi
