#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"

# shellcheck source=../lib/generated-input.sh
. "$repo_root/tests/lib/generated-input.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

tracked_generated=$(git ls-files 'generated/*')
if [ -n "$tracked_generated" ]; then
  fail "generated/ artifacts are still tracked in git"
fi

for sentinel in \
  .generated-input-sentinel/.keep \
  .yeet-and-yoink-input-sentinel/.keep; do
  if git ls-files --error-unmatch "$sentinel" >/dev/null 2>&1; then
    if git diff --name-only --diff-filter=D -- "$sentinel" | grep -q . \
      || git diff --cached --name-only --diff-filter=D -- "$sentinel" | grep -q .; then
      :
    else
      fail "sentinel placeholder is still tracked: $sentinel"
    fi
  fi
done

if rg -n 'nix_generated_eval[[:space:]]+\-\-impure|nix[[:space:]].*\-\-impure' tests/den tests/gpg-preset-passphrase.sh >/dev/null; then
  fail 'tests still rely on --impure instead of explicit generated/yeet inputs'
fi

if grep -Fq 'inputs.generated = {' flake.nix; then
  fail 'flake.nix must not contain a sentinel generated input declaration'
fi
if grep -Fq 'inputs.yeetAndYoink = {' flake.nix; then
  fail 'flake.nix must not contain a sentinel yeetAndYoink input declaration'
fi

test -f scripts/external-input-flake.sh \
  || fail 'scripts/external-input-flake.sh must exist'
test -f den/mk-config-outputs.nix \
  || fail 'den/mk-config-outputs.nix must exist'

grep -Fq 'lib.mkOutputs' flake.nix \
  || fail 'flake.nix must export lib.mkOutputs for wrapper flakes'
grep -Fq 'mk_wrapper_flake' tests/lib/generated-input.sh \
  || fail 'tests/lib/generated-input.sh must use mk_wrapper_flake'

if rg -n '../../../generated/' \
  den/aspects/features/secrets.nix \
  den/aspects/features/darwin-core.nix \
  den/aspects/hosts/vm-aarch64.nix >/dev/null; then
  fail 'den aspects still read repo-relative generated/ paths'
fi

grep -Fq 'external-input-flake.sh' docs/macbook.sh \
  || fail 'docs/macbook.sh must use the wrapper flake flow'
grep -Fq 'external-input-flake.sh' docs/vm.sh \
  || fail 'docs/vm.sh must use the wrapper flake flow'
grep -Fq 'external-input-flake.sh' den/aspects/features/shell-git.nix \
  || fail 'shell-git aliases must use the wrapper flake approach'
if rg -n -- '--impure' AGENTS.md >/dev/null; then
  fail 'AGENTS.md must not document --impure for flake-aware commands'
fi
grep -Fq 'external-input-flake.sh' AGENTS.md \
  || fail 'AGENTS.md must document the wrapper flake approach'
grep -Fq 'scripts/external-input-flake.sh' AGENTS.md \
  || fail 'AGENTS.md must show the wrapper script path'
grep -Fq 'path:$WRAPPER' AGENTS.md \
  || fail 'AGENTS.md must show wrapper-based flake references'
grep -Fq 'default_nix_config_dir()' docs/macbook.sh \
  || fail 'docs/macbook.sh must default NIX_CONFIG_DIR from the script checkout when available'
grep -Fq 'default_nix_config_dir()' docs/vm.sh \
  || fail 'docs/vm.sh must default NIX_CONFIG_DIR from the script checkout when available'
if rg -n '/home/m/Projects/yeet-and-yoink' tests/lib/generated-input.sh >/dev/null; then
  fail 'tests/lib/generated-input.sh must not fall back to /home/m/Projects/yeet-and-yoink'
fi

grep -Fq '.host:/nixos-generated' den/aspects/features/vmware.nix \
  || fail 'vmware aspect must mount the generated shared folder'
grep -Fq 'guestName = "nixos-generated"' docs/vm.sh \
  || fail 'docs/vm.sh must configure a nixos-generated shared folder'
grep -Fq 'vmrun -T fusion setSharedFolderState "$vmx" "$share_name" "$host_path" writable' docs/vm.sh \
  || fail 'docs/vm.sh must update shared-folder host paths for existing VMs'
grep -Fq 'vmrun -T fusion addSharedFolder "$vmx" "$share_name" "$host_path"' docs/vm.sh \
  || fail 'docs/vm.sh must add missing shared folders for existing VMs'
grep -Fq 'vm_ensure_required_shared_folders "$existing_vmx"' docs/vm.sh \
  || fail 'docs/vm.sh must reconcile shared folders before reusing an existing VM'
grep -Fq 'vm_ensure_required_shared_folders "$vmx"' docs/vm.sh \
  || fail 'docs/vm.sh must reconcile shared folders before switching the VM'

generated_input_dir >/dev/null

actual=$(nix_generated_eval \
  --raw \
  .#nixosConfigurations.vm-aarch64.config.sops.defaultSopsFile)

printf '%s' "$actual" | grep -q 'secrets.yaml' \
  || fail "sops.defaultSopsFile did not resolve through the external generated input"

printf 'PASS: no-sentinel wrapper flake design looks correct\n'
