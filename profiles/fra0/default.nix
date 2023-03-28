{ self }:
{
  activeModules = with self.nixosModules ; [
  ];

  components = {
    optionalComponents = [
      "cloud"
      "tippy"
      "traefik"
    ];

    blacklist = [ ];
  };

  homeModuleHelper.tippy = [
  ];


  extraConfiguration = { utils, ... }: {
    networking.hostName = "fra0";
  };
}
