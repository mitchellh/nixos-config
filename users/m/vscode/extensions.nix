{ pkgs }:
with pkgs.vscode-extensions; [
  # Themes
  dracula-theme.theme-dracula

  # Vim
  vscodevim.vim

  # Markdown
  yzhang.markdown-all-in-one
  bierner.markdown-mermaid

  # Nix
  bbenoist.nix

  # Python
  charliermarsh.ruff
  ms-python.python
  ms-python.vscode-pylance
  ms-python.debugpy

  # Jupyter
  ms-toolsai.jupyter
  ms-toolsai.jupyter-keymap
  ms-toolsai.jupyter-renderers

  # Rust
  rust-lang.rust-analyzer
  vadimcn.vscode-lldb

  # GitHub
  github.vscode-github-actions
  github.copilot-chat

  # Remote Development
  ms-vscode-remote.remote-ssh
  ms-vscode-remote.remote-ssh-edit
  ms-vscode.remote-explorer


  # Docker
  ms-azuretools.vscode-docker

  # Terraform
  hashicorp.terraform

  # LaTeX
  james-yu.latex-workshop

  # SQL
  # mtxr.sqltools

  # Swift
  # sweetpad.sweetpad

  # Additional extensions (add manually if not in nixpkgs):
  rooveterinaryinc.roo-cline
  alefragnani.project-manager
  anthropic.claude-code
  bodil.file-browser
  kahole.magit
  vspacecode.vspacecode
  vspacecode.whichkey
]
++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
  {
    name = "mono-bw";
    publisher = "anfeket";
    version = "1.0.0";
    sha256 = "sha256-pBGpckc4bOhM1x+Ne5r1sBrT5vr0m/VonS02MO1YdjE=";
  }
  {
    name = "vsnetrw";
    publisher = "danprince";
    version = "0.3.1";
    sha256 = "sha256-rxbpxRv6h8LIrLlpusSvBbeaAP4AwRkZTTcFeVukKLc=";
  }
  {
    name = "basedpyright";
    publisher = "detachhead";
    version = "1.38.1";
    sha256 = "sha256-KomVzNgm4CD3AMuJ7myZlU6R4bp97pNlnooYdEepQNo=";
  }
  {
    name = "tinymist";
    publisher = "myriad-dreamin";
    version = "0.14.10";
    sha256 = "sha256-ez7VRSVjPVDqXpscwB+PGSEXw34YHmAV14atnSYO0vg=";
  }
  {
    name = "chatgpt";
    publisher = "openai";
    version = "0.5.76";
    sha256 = "sha256-f9der+dngQmdTYHWcExVC/md4XTEckSYbRKWKf72C1g=";
  }
  {
    name = "opencode";
    publisher = "sst-dev";
    version = "0.0.13";
    sha256 = "sha256-6adXUaoh/OP5yYItH3GAQ7GpupfmTGaxkKP6hYUMYNQ=";
  }
  {
    name = "leaderkey";
    publisher = "jimmyzjx";
    version = "1.7.2";
    sha256 = "sha256-5XA7papKHca2U+9KdWAo2CEZCBXPNxFIjDkOC+Zym58=";
  }
  {
    name = "newyorkatnighttheme";
    publisher = "ggabi40";
    version = "1.0.7";
    sha256 = "sha256-Y4D3UPv6CxGveblMgjzgLf4c7eOgJc+9EJC7ay53gIo="; 
  }
  {
      name = "vscode-remote-control";
      publisher = "eliostruyf";
      version = "1.9.0";
      sha256 = "sha256-Iq0lP6OMB9ZMry1Wl6GovPmZGVjq/z8/Hy9HXcg5Nmw=";
  }
]
