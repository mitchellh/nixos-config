{ den, ... }: {
  den.aspects.macbook-pro-m1 = {
    includes = [
      den.aspects.darwin-core
      den.aspects.darwin-desktop
      den.aspects.homebrew
      den.aspects.launchd
    ];
  };
}
