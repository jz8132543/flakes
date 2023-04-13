{ self }:
{
  activeModules = with self.nixosModules ; [
  ];

  components = {
    optionalComponents = [
      "cloud"
      "tippy"
      "traefik"
      "postgres"
      "headscale"
      "tailscale"
    ];

    blacklist = [ ];
  };

  homeModuleHelper.tippy = [
  ];


  extraConfiguration = { utils, ... }: {
    networking.hostName = "fra0";
  };
}
