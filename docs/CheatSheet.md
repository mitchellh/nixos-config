# CheatSheet

## Nix & NixOS

### Main commands:

- `nix build` (./nix3-build.md) - build a derivation or fetch a store path
- `nix develop` (./nix3-develop.md) - run a bash shell that provides the build environment of a derivation
- `nix flake` (./nix3-flake.md) - manage Nix flakes
- `nix help` (./nix3-help.md) - show help about nix or a particular subcommand
- `nix profile` (./nix3-profile.md) - manage Nix profiles
- `nix repl` (./nix3-repl.md) - start an interactive environment for evaluating Nix expressions
- `nix run` (./nix3-run.md) - run a Nix application
- `nix search` (./nix3-search.md) - search for packages
- `nix shell` (./nix3-shell.md) - run a shell in which the specified packages are available

### Infrequently used commands:

- `nix bundle` (./nix3-bundle.md) - bundle an application so that it works outside of the Nix store
- `nix copy` (./nix3-copy.md) - copy paths between Nix stores
- `nix edit` (./nix3-edit.md) - open the Nix expression of a Nix package in $EDITOR
- `nix eval` (./nix3-eval.md) - evaluate a Nix expression
- `nix log` (./nix3-log.md) - show the build log of the specified packages or paths, if available
- `nix path-info` (./nix3-path-info.md) - query information about store paths
- `nix registry` (./nix3-registry.md) - manage the flake registry
- `nix why-depends` (./nix3-why-depends.md) - show why a package has another package in its closure

### Utility/scripting commands:

- `nix daemon` (./nix3-daemon.md) - daemon to perform store operations on behalf of non-root clients
- `nix describe-stores` (./nix3-describe-stores.md) - show registered store types and their available options
- `nix hash` (./nix3-hash.md) - compute and convert cryptographic hashes
- `nix key` (./nix3-key.md) - generate and convert Nix signing keys
- `nix nar` (./nix3-nar.md) - create or inspect NAR files
- `nix print-dev-env` (./nix3-print-dev-env.md) - print shell code that can be sourced by bash to reproduce the build environment of a derivation
- `nix realisation` (./nix3-realisation.md) - manipulate a Nix realisation
- `nix show-config` (./nix3-show-config.md) - show the Nix configuration
- `nix show-derivation` (./nix3-show-derivation.md) - show the contents of a store derivation
- `nix store` (./nix3-store.md) - manipulate a Nix store

### Commands for upgrading or troubleshooting your Nix installation:

- `nix doctor` (./nix3-doctor.md) - check your system for potential problems and print a PASS or FAIL for each check
- `nix upgrade-nix` (./nix3-upgrade-nix.md) - upgrade Nix to the latest stable version


### Listing installed packages
```bash
nix-env -q
nix profile list
```

### Listing available packages
```bash
nix-env -qaP
# Listing specific version
nix-env -qaP | grep nodejs
```

### Installing packages
```bash
nix-env -iA nixpkgs.gitFull
# Installing pkgs in folders (.nix)
nix profile install -f nomad-bin.nix
nix profile install nixpkgs#hello
```

### Removing packages
```bash
nix-env -e git
nix profile remove 0
nix profile remove /nix/store/d2ygyyyig907d10j6qx65zsg3mqai4mq-nomad-bin-1.0.4
```
(It's best you copy paste the name, which you got from `nix-env -q`)

### Updating packages

First update your channel
```bash
nix-channel --update
```

See what's available
```bash
nix-env -qc
```

Update everything
```bash
nix-env -u --keep-going --leq
```

### Show dependencies
```bash
nix-store --query --references\
  $(nix-instantiate '<nixpkgs>' -A emacs)
```

Print the store path of the `asdf-vm` package
```bash
nix eval --raw 'nixpkgs#asdf-vm'
nix eval --raw 'nixpkgs#asdf-vm.pname'
nix eval --raw 'nixpkgs#asdf-vm.version'
```
