{ den, ... }: {
  den.aspects.identity = {
    includes = [
      den.provides.define-user
      den.provides.primary-user
      (den.provides.user-shell "zsh")
    ];
  };
}
