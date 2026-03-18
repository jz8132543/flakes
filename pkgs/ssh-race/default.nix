{
  stdenv,
  lib,
  go,
  ...
}:
stdenv.mkDerivation {
  pname = "ssh-race";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [ go ];

  buildPhase = ''
    runHook preBuild
    export CGO_ENABLED=0
    export GOCACHE=$TMPDIR/go-cache
    mkdir -p "$GOCACHE"
    go build -trimpath -ldflags "-s -w" -o ssh-race .
    runHook postBuild
  '';

  checkPhase = ''
    runHook preCheck
    export CGO_ENABLED=0
    export GOCACHE=$TMPDIR/go-cache
    mkdir -p "$GOCACHE"
    go test ./...
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 ssh-race $out/bin/ssh-race
    runHook postInstall
  '';

  meta = with lib; {
    description = "ProxyCommand helper that races SSH host suffixes and falls back to the original host";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "ssh-race";
  };
}
