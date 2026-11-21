{ lib }:
let
  suite = import ./default.nix;
  inventory = {
    primary = evaluate "primary" true;
    secondary = evaluate "secondary" false;
    disabled = {
      config.services.livekitSuite._meta.enable = false;
      pkgs = throw "disabled pkgs forced";
    };
    unrelated = {
      config.system.build.toplevel = throw "unrelated toplevel forced";
    };
  };
  evaluate =
    name: primary:
    lib.evalModules {
      specialArgs = {
        pkgs = throw "discovery instantiated pkgs";
        self.nixosConfigurations = inventory;
      };
      modules = [
        suite.all
        ({ ... }: {
          _module.check = false;
          services.livekitSuite = {
            redis.enable = primary;
            web.enable = primary;
            _meta = {
              enable = lib.mkDefault true;
              domain = "${name}.example.org";
              httpsPort = if primary then 443 else 50569;
              signalingPath = if primary then "" else "/livekit";
              turnDomain = if primary then "turn-primary.example.org" else "secondary.example.org";
              privateAddress = "${name}.internal";
              region = name;
              inherit primary;
            };
          };
        })
      ];
    };
  cfg = inventory.primary.config.services.livekitSuite;
  colmena = lib.evalModules {
    specialArgs = {
      pkgs = throw "Colmena discovery forced pkgs";
      nodes = lib.mapAttrs (_: value: value.config or value) inventory;
    };
    modules = [
      suite.all
      { _module.check = false; }
    ];
  };
in
assert cfg._meta.enable;
assert builtins.length cfg.topology.sfuNodes == 2;
assert builtins.length cfg.topology.redisNodes == 1;
assert cfg.topology.primary.name == "primary";
assert cfg.topology.primary.url == "wss://primary.example.org";
assert (builtins.elemAt cfg.topology.nodes 1).url == "wss://secondary.example.org:50569/livekit";
assert builtins.length cfg.topology.iceServers == 4;
assert builtins.length cfg.topology.turnServers == 6;
assert colmena.config.services.livekitSuite.topology.nodes == cfg.topology.nodes;
assert
  cfg.settings.media.video.codecPriority == [
    "av1"
    "h265"
    "vp9"
    "h264"
  ];
{
  lazyMetadata = true;
  noPackages = true;
  noToplevel = true;
  colmena = true;
}
