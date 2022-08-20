{
  self,
  inputs,
  ...
}: {
  overlays = [
    inputs.sops-nix.overlay
    inputs.nixos-cn.overlay
  ];
}
