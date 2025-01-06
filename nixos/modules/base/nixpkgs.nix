{
  inputs,
  getSystem,
  config,
  lib,
  ...
}:
let
  packages = [
    inputs.sops-nix.overlays.default
    inputs.pastebin.overlays.default
    inputs.neovim-nightly-overlay.overlays.default
    # inputs.nixd.overlays.default
    # inputs.nvfetcher.overlays.default
    (
      _final: prev:
      let
        inherit (prev.stdenv.hostPlatform) system;
        inherit ((getSystem system).allModuleArgs) inputs';
      in
      {
        python312 = prev.python312.override {
          # deliberate typo. don't copy this into your config blindly
          packageOverrides = _final: prev: {
            pysaml2 = prev.pysaml2.overridePythonAttrs (orig: {
              disabledTests = orig.disabledTests ++ [
                "test_encrypted_response_6"
                "test_validate_cert_chains"
                "test_validate_with_root_cert"
              ];
            });
          };
        };
        matrix-synapse-unwrapped = prev.matrix-synapse-unwrapped.overridePythonAttrs { doCheck = false; }; # todo skip right tests
        inherit (inputs'.nix-gc-s3.packages) nix-gc-s3;
        inherit (inputs'.headscale.packages) headscale;
        clash2sing-box = inputs'.clash2sing-box.packages.default;
        tailscale = prev.tailscale.overrideAttrs (old: {
          # tailscale = inputs'.tailscale.packages.tailscale.overrideAttrs (old: {
          # subPackages = old.subPackages ++ [ "cmd/derper" ] ++ [ "cmd/derpprobe" ];
          subPackages = [
            "cmd/tailscaled"
            "cmd/derper"
            "cmd/stunc"
            "cmd/hello"
          ];
          postInstall = lib.strings.concatStrings [
            "cp $out/bin/derper $out/bin/derp && "
            old.postInstall
          ];
        });
      }
    )
  ];
  lateFixes = _final: _prev: {
  };
  lastePackages = [
    (import "${config.lib.self.path}/pkgs").overlay
  ];
in
{
  nixpkgs = {
    config = {
      allowUnfree = true;
      allowBroken = true;
      nvidia.acceptLicense = true;
      binary-caches-parallel-connections = 16;
      permittedInsecurePackages = [
        "openssl-1.1.1w"
        "electron-27.3.11"
        "nix-2.24.5"
      ];
      allowUnfreePackages = [ "terraform" ];
    };
    overlays = packages ++ [ lateFixes ] ++ lastePackages;
  };
}
