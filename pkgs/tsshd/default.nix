{
  pkgs,
  buildGo126Module,
  sources,
  python3,
}:
let
  upstream = pkgs.callPackage (pkgs.path + "/pkgs/by-name/ts/tsshd/package.nix") {
    buildGoModule = buildGo126Module;
  };
in
upstream.overrideAttrs (old: {
  version = sources.tsshd.packageVersion;
  inherit (sources.tsshd) src;
  patches = (old.patches or [ ]) ++ [ ./setup.patch ];
  vendorHash = "sha256-4gT9LC+OTzpBNiWaVNFyNzK4UF3zLNNZl0uj/OJb/6Q=";
  subPackages = [ "cmd/tsshd" ];
  nativeCheckInputs = (old.nativeCheckInputs or [ ]) ++ [ python3 ];
  checkPhase = ''
    runHook preCheck
    go test ./tsshd
    runHook postCheck
  '';
  passthru = (old.passthru or { }) // {
    autoTransportVersion = 1;
  };
  meta = old.meta // {
    description = "Pinned on-demand tsshd with bounded transactional setup cancellation";
    changelog = "https://github.com/trzsz/tsshd/releases/tag/v0.1.10";
  };
})
