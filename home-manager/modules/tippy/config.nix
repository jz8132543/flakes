{
  config,
  osConfig,
  pkgs,
  ...
}: {
  sops.age.keyFile = "/var/lib/sops-nix/key";
  sops.defaultSopsFile = osConfig.sops-file.get "common.yaml";
  sops.secrets."ssh/id_ed25519".path = ".ssh/id_ed25519";
  home.file.".ssh/id_ed25519.pub".source = pkgs.writeText "pub" config.lib.self.data.ssh.i;
  home.global-persistence = {
    directories = [
      ".cache/nix"
    ];
  };
  home.sessionVariables =
    if osConfig.networking.fw-proxy.enable
    then osConfig.networking.fw-proxy.environment
    else {};

  home.packages = with pkgs; [
    duf
    sops
    home-manager
    nixd
  ];
}
