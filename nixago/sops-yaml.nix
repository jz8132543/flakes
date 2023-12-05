{lib}: let
  main = "23232A6D050ACE46DF02D72B84A772A8519FC163";
  yubikeys = {
    # TODO https://github.com/mozilla/sops/issues/1103
    # yubikey5 = "age1yubikey1qda6pkn5cf75zrx6kx4wdx287dlege8eucuhnr9zjl94dzsg56afwtma6nz";
  };
  yubikeyKeys = lib.attrValues yubikeys;
  github = "age170nax8h00thyfumectwsrz2vk2l39k80urwzghez84acppq97fushqjtrd";
  hosts = {
    surface = {
      key = "age1934xpm9at83g823dzwm3wxj64apvrx40wcv8ms2p9gvgxdxwsp3s0rvpyc";
      owned = true;
    };
    vmware = {
      key = "age1usgse67dhelp4897fk2h4w96jsl6qpgzhukngdryua8nv0m0fyms8ktw2v";
      owned = true;
    };
    fra0 = {
      key = "age15f7j88sget6mun9tgfc4e0qdptev982jcxfaf0js2ky52t00vsaqhywj8m";
      owned = true;
    };
    fra1 = {
      key = "age14x2wz4k3xr7u0sgx5hl5wjejynjh4pkw59ccsfqvw9vrctyy54qsqvfrw4";
      owned = true;
    };
    ams0 = {
      key = "age16rc6cs8fhplzwh938d3zxq8pke7pgxerzms0dgkdgq7he99c3ccs4emnhd";
      owned = true;
    };
    dfw0 = {
      key = "age1tvfl7y78hv2egs45nqtp7nlydqrrq2twjr47m2028lh68qtqwuxs9wxk3v";
      owned = true;
    };
    dfw1 = {
      key = "age1pjtlq295c5gul5naxthwu5j2a85kc5090kuyp9c3e3rvdvefyq9ql9uujg";
      owned = true;
    };
  };
  ownedHostKeys = lib.mapAttrsToList (_: cfg: cfg.key) (lib.filterAttrs (_: cfg: cfg.owned) hosts);
  allHostKeys = lib.mapAttrsToList (_: cfg: cfg.key) hosts;

  mkHostCreationRule = host: key: {
    path_regex = "^secrets/(terraform/)?hosts/${host}(\.plain)?\.yaml$";
    key_groups = [
      {
        pgp = [main];
        age = [key github];
      }
    ];
  };
in {
  creation_rules =
    [
      {
        path_regex = "^secrets/(terraform/)?common\.yaml$";
        key_groups = [
          {
            pgp = [main];
            age = yubikeyKeys ++ allHostKeys ++ [github];
          }
        ];
      }
      {
        path_regex = "^secrets/(terraform/)?infrastructure\.yaml$";
        key_groups = [
          {
            pgp = [main];
            age = yubikeyKeys ++ allHostKeys ++ [github];
          }
        ];
      }
      {
        path_regex = "^secrets/terraform-inputs\.yaml$";
        key_groups = [
          {
            pgp = [main];
            age = yubikeyKeys ++ [github];
          }
        ];
      }
      {
        path_regex = "^secrets/terraform-outputs\.yaml$";
        key_groups = [
          {
            pgp = [main];
            age = yubikeyKeys ++ [github];
          }
        ];
      }
      {
        path_regex = "terraform.(tfstate|plan)$";
        key_groups = [
          {
            pgp = [main];
            age = yubikeyKeys ++ [github];
          }
        ];
      }
      {
        path_regex = "^/tmp/encrypt.*$";
        key_groups = [
          {
            pgp = [main];
            age = yubikeyKeys ++ [github];
          }
        ];
      }
    ]
    ++ lib.mapAttrsToList (host: cfg: mkHostCreationRule host cfg.key) hosts;
}
