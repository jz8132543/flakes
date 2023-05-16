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
      key = "age15f7j88sget6mun9tgfc4e0qdptev982jcxfaf0js2ky52t00vsaqhywj8m";
      owned = true;
    };
    surface = {
      key = "age1934xpm9at83g823dzwm3wxj64apvrx40wcv8ms2p9gvgxdxwsp3s0rvpyc";
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
