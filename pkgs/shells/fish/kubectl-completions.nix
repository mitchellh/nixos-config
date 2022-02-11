/* copy from yurrriq/dotfiles to fix missing fish kubectl completions.
 * using `niv add evanlucas/fish-kubectl-completions`
 */
{ stdenv, fetchFromGitHub }:

stdenv.mkDerivation rec {
  pname = "fish-kubectl-completions";
  version = "bbe3b831";

  src = fetchFromGitHub {
    owner = "evanlucas";
    repo = pname;
    rev = version;
    hash = "sha256-+jo6Zx6nlA5QhQ+3Vru+QbKjCwIxPEvrlKWctffG3OQ=";
  };
  dontBuild = true;
  dontCheck = true;
  installPhase = ''
    install -m555 -Dt $out/share/fish/vendor_completions.d/ completions/kubectl.fish
  '';
}
