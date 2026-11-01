{
  pkgs,
  buildGo126Module,
  fetchFromGitHub,
  python3,
}:
let
  upstream = pkgs.callPackage (pkgs.path + "/pkgs/by-name/ts/tsshd/package.nix") {
    buildGoModule = buildGo126Module;
  };
in
upstream.overrideAttrs (old: {
  version = "0.1.10";
  src = fetchFromGitHub {
    owner = "trzsz";
    repo = "tsshd";
    rev = "aadccecc014bff097e8b50e2af76a4449a0f561a";
    hash = "sha256-GbP3im6E5eYyGIkst70YJJ/MQ400Z1m6EVm9X8szJWg=";
  };
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
