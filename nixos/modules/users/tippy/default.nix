{
  config,
  pkgs,
  ...
}: let
  name = "tippy";
  homeDirectory = "/home/${name}";
in {
  users.mutableUsers = true;
  users.users.${name} = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = ["wheel"];
    openssh.authorizedKeys.keys = [config.lib.self.data.ssh.i];
    hashedPassword = "$6$0gRnTBQjBv9ipXZz$AEBVrBbWXgzZ0IICD1HVWeCwqELFe85.ePsOOdkvFM1E6/sKvQUUesvXhQN519Ud33RsqA3h5z.4luO8Jk4Ls/";
  };
  security.sudo.wheelNeedsPassword = false;
  sops.secrets."ssh/id_ed25519" = {
    neededForUsers = true;
  };

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
    home.persistence."/nix/persist${homeDirectory}" = {
      directories = [
        "source"
        ".local/share/direnv"
      ];
      files = [
      ];
      allowOther = true;
    };
  };
}
