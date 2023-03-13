{ self }:
{
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
