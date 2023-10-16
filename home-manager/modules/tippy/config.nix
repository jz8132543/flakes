{
  config,
  pkgs,
  ...
}: {
  sops.secrets."ssh/id_ed25519".path = ".ssh/id_ed25519";
  home.file.".ssh/id_ed25519.pub".source = pkgs.writeText "pub" config.lib.self.data.ssh.i;
  home.global-persistence = {
    directories = [
      ".cache/nix"
    ];
  };

  home.packages = with pkgs; [
    duf
    sops
    home-manager
    nixd
  ];
}
