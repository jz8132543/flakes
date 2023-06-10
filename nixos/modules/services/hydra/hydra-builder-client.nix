{config, ...}: let
  keyFile = "nix-build-machines/hydra-builder/key";
  machineFile = "nix-build-machines/hydra-builder/machines";
in {
  nix = {
    distributedBuilds = true;
    extraOptions = ''
      builders-use-substitutes = true
    '';
  };
  environment.etc.${machineFile}.text = ''
    hydra-builder@fra0  x86_64-linux,i686-linux /etc/${keyFile} 4 1 kvm,nixos-test,benchmark,big-parallel
    hydra-builder@fra1  x86_64-linux,i686-linux /etc/${keyFile} 4 1 kvm,nixos-test,benchmark,big-parallel
  '';
  sops.secrets."hydra/builder_private_key" = {
    neededForUsers = true; # needed for /etc
  };
  environment.etc.${keyFile} = {
    mode = "444";
    # user = config.users.users.hydra-builder-client.name;
    # group = config.users.groups.hydra-builder-client.name;
    source = config.sops.secrets."hydra/builder_private_key".path;
  };
  # users.users.hydra-builder-client = {
  #   uid = config.ids.uids.hydra-builder-client;
  #   isSystemUser = true;
  #   group = config.users.groups.hydra-builder-client.name;
  # };
  # users.groups.hydra-builder-client = {
  #   gid = config.ids.gids.hydra-builder-client;
  # };
}
