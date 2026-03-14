{ den, ... }: {
  den.aspects.wsl = {
    includes = [
      den.aspects.wsl-system
    ];
  };
}
