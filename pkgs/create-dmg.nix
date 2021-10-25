{ stdenv, fetchFromGitHub, makeWrapper }:

stdenv.mkDerivation rec {
  pname = "create-dmg";
  version = "1.0.0.7";

  src = fetchFromGitHub {
    owner = "andreyvit";
    repo = pname;
    rev = "v${version}";
    sha256 = "0cczlp7ds0ylczgb2sn0nzl0jlhy41b7xy40fz4caal2agm7wdbv";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    makeWrapper $src/create-dmg $out/bin/create-dmg
  '';

  meta = with stdenv.lib; {
    homepage = "https://github.com/andreyvit/create-dmg";
    description = "A shell script to build fancy DMGs";
    license = licenses.mit;
  };
}
