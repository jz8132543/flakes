{ self }:
{
  targetHost = null;
  targetPort = 22;

  activeModules = with self.nixosModules ; [
  ];

  components = {
    optionalComponents = [
      "tippy"
      "desktop"
      "cn"
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
