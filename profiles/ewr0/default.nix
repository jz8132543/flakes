{ self }:
{
  targetHost = "ewr0.dora.im";
  targetPort = 22;

  activeModules = with self.nixosModules ; [
  ];

  components = {
    optionalComponents = [
      "cloud"
      "tippy"
    ];

    blacklist = [ ];
  };

  homeModuleHelper.tippy = [
  ];


  extraConfiguration = { utils, ... }: {
    networking.hostName = "ewr0";
  };
}
