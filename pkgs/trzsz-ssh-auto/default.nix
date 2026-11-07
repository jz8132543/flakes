{
  trzsz-ssh,
  buildGo126Module,
  sources,
}:
(trzsz-ssh.override { buildGoModule = buildGo126Module; }).overrideAttrs (old: {
  pname = "trzsz-ssh-auto";
  version = sources.trzsz-ssh-auto.packageVersion;
  inherit (sources.trzsz-ssh-auto) src;
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
