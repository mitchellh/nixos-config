#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"

grep -Fq 'inputs.den.url = "github:vic/den";' flake.nix
grep -Fq 'inputs.den.flakeModule' den/default.nix
test ! -e den/legacy.nix
grep -Fq 'inherit (den.flake) nixosConfigurations darwinConfigurations;' den/mk-config-outputs.nix

# flake-aspects must be a direct input in flake.nix (den's lib.nix requires
# inputs.flake-aspects.lib, so every consumer flake must declare it explicitly).
grep -Fq 'flake-aspects.url = "github:vic/flake-aspects"' flake.nix

# flake.lock must carry a root-level entry for flake-aspects (confirms lock is
# in sync with the flake.nix declaration above).
python3 - <<'PYEOF'
import json, sys
with open("flake.lock") as f:
    lock = json.load(f)
root_inputs = lock["nodes"]["root"].get("inputs", {})
if "flake-aspects" not in root_inputs:
    print("FAIL: flake.lock root is missing required 'flake-aspects' input", file=sys.stderr)
    sys.exit(1)
PYEOF
