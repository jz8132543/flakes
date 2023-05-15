{ lib }:
let
  main = "23232A6D050ACE46DF02D72B84A772A8519FC163";
  yubikeys = {
    # TODO https://github.com/mozilla/sops/issues/1103
    # yubikey5 = "age1yubikey1qda6pkn5cf75zrx6kx4wdx287dlege8eucuhnr9zjl94dzsg56afwtma6nz";
  };
  yubikeyKeys = lib.attrValues yubikeys;
  hosts = {
    fra0 = {
      key = "age1qrrwcee244ak7ax9xwuxdttzsan24g655lpmvry3275j6v4n2pesjwyawu";
      owned = true;
    };
  };
  ownedHostKeys = lib.mapAttrsToList (_: cfg: cfg.key) (lib.filterAttrs (_: cfg: cfg.owned) hosts);
  allHostKeys = lib.mapAttrsToList (_: cfg: cfg.key) hosts;

  mkHostCreationRule = host: key: {
    path_regex = "^secrets/(terraform/)?hosts/${host}(\.plain)?\.yaml$";
    key_groups = [
      {
        pgp = [ main ];
        age = [ key ];
      }
    ];
  };
in
{
  creation_rules =
    [
      {
        path_regex = "^secrets/(terraform/)?common\.yaml$";
        key_groups = [
          {
            pgp = [ main ];
            age = yubikeyKeys ++ ownedHostKeys;
          }
        ];
      }
    ]
    ++ lib.mapAttrsToList (host: cfg: mkHostCreationRule host cfg.key) hosts;
}
