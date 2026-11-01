{
  trzsz-ssh,
  buildGo126Module,
  fetchFromGitHub,
}:
(trzsz-ssh.override { buildGoModule = buildGo126Module; }).overrideAttrs (old: {
  pname = "trzsz-ssh-auto";
  version = "0.1.27";
  src = fetchFromGitHub {
    owner = "trzsz";
    repo = "trzsz-ssh";
    rev = "7dc4f01a9bc29b7775852bf6531745df2d1a0151";
    hash = "sha256-wiObvHGSJdf8qXO1u7PvLdaQ1cvkLAgmQoGkw3hUMkQ=";
  };
  patches = (old.patches or [ ]) ++ [ ./auto.patch ];
  vendorHash = "sha256-iftza3ymE6qyAFoPm+JoiAtUsjbSoNvYFnuXle1vVII=";
  modPostBuild = (old.modPostBuild or "") + ''
    patch -p1 -d vendor/github.com/trzsz/tsshd < ${./dependency.patch}
  '';
  subPackages = [ "cmd/tssh" ];
  checkPhase = ''
    runHook preCheck
    go test -mod=vendor ./tssh ./vendor/github.com/trzsz/tsshd/tsshd
    runHook postCheck
  '';
  passthru = (old.passthru or { }) // {
    autoTransportVersion = 1;
  };
  meta = old.meta // {
    description = "Pinned tssh with authenticated transactional KCP selection and TCP fallback";
    changelog = "https://github.com/trzsz/trzsz-ssh/releases/tag/v0.1.27";
    mainProgram = "tssh";
  };
})
