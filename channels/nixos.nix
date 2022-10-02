{ self, inputs, ... }: {
  overlays = [
    ../pkgs/default.nix
    inputs.nur.overlay
    inputs.sops-nix.overlay
    inputs.nixos-cn.overlay
  ];
}
