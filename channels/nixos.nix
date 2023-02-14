{ self, inputs, ... }: {
  overlays = [
    inputs.nur.overlay
    inputs.sops-nix.overlay
    inputs.nixos-cn.overlay
    # inputs.neovim-nightly-overlay.overlay
  ];
}
