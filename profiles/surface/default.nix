{ self }:
{
  activeModules = with self.nixosModules ; [
    v2raya
  ];

  components = {
    optionalComponents = [
      "cloud"
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
