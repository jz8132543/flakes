{ pkgs, hmUsers, config, lib, ... }:
let name = "tippy"; homeDirectory = "/home/${name}"; ssh_link = config.sops.secrets.id_ed25519.path;
  aws_link = config.sops.secrets.s3_credentials.path;
in {
  sops.secrets.id_ed25519 = {
    format = "binary";
    owner = config.users.users.${name}.name;
    group = config.users.users.${name}.group;
    sopsFile = config.sops.secretsDir + /id_ed25519.keytab;
  };

  environment.global-persistence.user.users = [ name ];
  home-manager.users.${name} = { config, suites, ... }: {
    imports = suites.base;
    home.file.".ssh/id_ed25519".source =
      config.lib.file.mkOutOfStoreSymlink ssh_link;
    home.file.".aws/credentials".source =
      config.lib.file.mkOutOfStoreSymlink aws_link;
    home.global-persistence = {
      enable = true;
      home = homeDirectory;
      directories = [
        "Source"
        ".local/share/direnv"
      ];
    };
  };

  environment.etc."nixos".source = "${homeDirectory}/Source/flakes";

  security.sudo.wheelNeedsPassword = false;
  users = {
    mutableUsers = true;
    users.${name} = {
      isNormalUser = true;
      home = homeDirectory;
      extraGroups = [ "wheel" "tty" "video" "audio" "libvirtd" "kvm" ];
      shell = pkgs.zsh;
      hashedPassword = "$6$GMMZ.rYjvVSpsvDl$dfCbuPkqhBMJT6Pa/GtEdMXjRVe1GYAqgDu4AuF2mSerE3ARiNfRO82.7jkhZOtnEvY4pvstmoiWhugv0kSDR1";
      openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCv8JCnlVW9uhKcAi649elGFANFaFzzoGfmFzMqjNNh55yLo19XZCshMsUL2+85oz/+Mw4zt/wVsFcEtulrT/O5PUaVZzGoHaeeGcVQZsI85j3OeXJtZDnjO2Y3qZfbWVRZ4V9DisjnwL+bzSgpc14htY56AHo1+WaXTcYuf1pGLseldZwbhg+QCzVVWRw2ZXFE3q62Jvtip16fC0su+U5YtTIkanrvcHRruAgq3PdOlHo/9nDxw66Kf1m+HggHTVCHuCJI/+gCYc0nLc1qpJL5v3hgEn+laVr3Us+AkkAEVPZdgZEtZYxSmj1LpSajsnFmH9goJOBQHHxEsff3Wdd528SLhGAILSYemKgA7nL0zOSPTCk3mEORlSdwmFITiNGUrJ1WueGAZsxfrnbwmAIYMnEiAj/+1MmcySk8upAFYyjhJ5cYYphNJohIbrWd/Bgwpr3Qp/Tb/l3sQVKqELmpej41YDVm/T+4bvz3BHXv9CIBrNJPYLIspqZJiQcBmKM= tippy@DESKTOP-PMU48VM"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJHUUFSNsaiMVMRtDl+Oq/7I2yViZAENbApEeCsbLJnq"
      ];
    };
  };
}
