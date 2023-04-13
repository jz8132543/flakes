{ self }:
{
  activeModules = with self.nixosModules ; [
  ];

  components = {
    optionalComponents = [
      "cloud"
      "tippy"
      "traefik"
      "tailscale"
      "v2ray"
    ];

    blacklist = [ ];
  };

  homeModuleHelper.tippy = [
  ];


  extraConfiguration = { utils, ... }: {
    networking.hostName = "sin0";
  };
}
