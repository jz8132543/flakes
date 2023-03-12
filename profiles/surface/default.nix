{ self }:
{
  targetHost = null;
  targetPort = 22;

  activeModules = with self.nixosModules ; [
  ];

  components = {
    optionalComponents = [
      "cloud"
      "tippy"
      "desktop"
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
