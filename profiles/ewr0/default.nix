{ self }:
{
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
