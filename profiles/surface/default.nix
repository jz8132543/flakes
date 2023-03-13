{ self }:
{
  targetHost = "surface.dora.im";
  targetPort = 22;

  activeModules = with self.nixosModules ; [
v2raya
  ];

  components = {
    optionalComponents = [
      "tippy"
      "desktop"
      "cn"
      # "proxy"
    ];

    blacklist = [ ];
  };

  homeModuleHelper.tippy = [
    "desktop"
  ];


  extraConfiguration = { utils, ... }: {
    networking.hostName = "surface";
  };
}
