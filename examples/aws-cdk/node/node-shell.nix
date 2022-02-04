# nix-shell --pure --show-trace node-shell.nix

with (import <nixpkgs> {});
mkShell {
  buildInputs = [
    nodejs-14_x       #v14.18.3
    yarn              #1.22.17
    awscli            #aws-cli/1.20.54 Python/3.9.6 Linux/5.15.13 botocore/1.21.54
  ];
  shellHook = ''
      mkdir -p .nix-node
      export NODE_PATH=$PWD/.nix-node
      export NPM_CONFIG_PREFIX=$PWD/.nix-node
      export PATH=$NODE_PATH/bin:$PATH

      npm install -g aws-cdk       #global not working

      node --version
      yarn --version
      npm --version        #6.14.15
      aws --version
      cdk --version        #2.10.0 (build e5b301f)
  '';
}
