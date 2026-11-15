let
  role = module: { lib, ... }: {
    imports = [
      ./options.nix
      ./discovery.nix
      ./credentials.nix
      module
    ];
    services.livekitSuite._meta.enable = lib.mkDefault true;
  };
in
{
  all = {
    imports = [
      (role ./sfu.nix)
      (role ./turn.nix)
      (role ./web.nix)
      (role ./redis.nix)
    ];
  };
  sfu = role ./sfu.nix;
  turn = role ./turn.nix;
  web = role ./web.nix;
  redis = role ./redis.nix;
}
