{
  config,
  pkgs,
  ...
}: let
  name = "${baseNameOf ./.}";
  homeDirectory = "/home/${name}";
in {
  users.mutableUsers = true;
  users.users.${name} = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = ["wheel" "cdrom" "libvirtd" "acme" "systemd-resolve"];
    openssh.authorizedKeys.keys = [config.lib.self.data.ssh.i];
    hashedPassword = "$6$0gRnTBQjBv9ipXZz$AEBVrBbWXgzZ0IICD1HVWeCwqELFe85.ePsOOdkvFM1E6/sKvQUUesvXhQN519Ud33RsqA3h5z.4luO8Jk4Ls/";
  };
  security.sudo.wheelNeedsPassword = false;
  sops.secrets."ssh/id_ed25519" = {
    neededForUsers = true;
  };

  nix.settings.trusted-users = [name];
  environment.global-persistence.user.users = [name];
  home-manager.users.${name} = {
    hmModules,
    osConfig,
    ...
  }: {
    imports =
      hmModules.${name}.all
      ++ (
        if osConfig.services.xserver.enable
        then hmModules.desktop.all
        else []
      );
    home.global-persistence = {
      enable = true;
      home = homeDirectory;
      directories = [
        "source"
        ".local/share/direnv"
      ];
    };
  };
}
