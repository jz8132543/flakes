{ self, inputs, ... }: {
  overlays =
    [ inputs.nur.overlay inputs.sops-nix.overlay inputs.nixos-cn.overlay ];
}
