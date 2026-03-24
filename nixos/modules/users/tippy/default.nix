{
  config,
  pkgs,
  ...
}:
let
  name = "${baseNameOf ./.}";
  homeDirectory = "/home/${name}";
in
{
  users.mutableUsers = true;
  users.users.${name} = {
    isNormalUser = true;
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "networkmanager"
      "lp"
      "lpadmin"
      "scanner"
      "video"
      "render"
      "cdrom"
      "libvirtd"
      "acme"
      "systemd-resolve"
      "aria2"
    ];
    openssh.authorizedKeys.keys = [ config.lib.self.data.ssh.i ];
    hashedPassword = "$6$0gRnTBQjBv9ipXZz$AEBVrBbWXgzZ0IICD1HVWeCwqELFe85.ePsOOdkvFM1E6/sKvQUUesvXhQN519Ud33RsqA3h5z.4luO8Jk4Ls/";
  };
  security.sudo.wheelNeedsPassword = false;
  # Keep this as a regular secret (not `neededForUsers`) so image builds that
  # run `nixos-install` don't fail when the SOPS key on /persist isn't present yet.
  sops.secrets."ssh/id_ed25519" = { };

  nix.settings.trusted-users = [ name ];
  environment.global-persistence.user.users = [ name ];
  programs.nh.flake = "${homeDirectory}/source/flakes";
  # environment.etc."nixos".source = "${homeDirectory}/source/flakes";
  home-manager.users.${name} =
    {
      hmModules,
      osConfig,
      ...
    }:
    {
      imports =
        hmModules.${name}.all ++ (if osConfig.services.xserver.enable then hmModules.desktop.all else [ ]);
      home.global-persistence = {
        enable = true;
        home = homeDirectory;
        directories = [
          {
            directory = "source";
            mode = "0777";
          }
          ".local/share/direnv"
        ];
      };
    };
  systemd.tmpfiles.rules = [
    "d  ${homeDirectory}/source                 775 ${name} users -"
    "d  ${homeDirectory}/.ssh                   700 ${name} users -"
  ];

  # systemd.tmpfiles.rules = [
  #   # "A+ ${homeDirectory}/source - - - - group::rw,other::rw"
  #   # "A+ ${homeDirectory}/source - - - - default:group::rw,default:other::rw"
  # ];
}
