{ config, lib, ... }:
let
  hasNextcloud = config.services.nextcloud.enable or false;
  hasSpreed = config.services.nextcloud-spreed-signaling.enable or false;
  spreedOwner = if hasSpreed then "nextcloud-spreed-signaling" else "root";
  spreedGroup = if hasSpreed then "nextcloud-spreed-signaling" else "root";
in
{
  # ── Sops 密钥声明 ──────────────────────────────────────────
  sops.secrets = {
    "password" = lib.mkIf hasNextcloud {
      restartUnits = [ "nextcloud-setup.service" ];
      mode = "0444";
    };

    "nextcloud/oidc-secret" = lib.mkIf hasNextcloud {
      restartUnits = [ "nextcloud-setup.service" ];
    };

    "nextcloud/turn-secret" = lib.mkIf (hasNextcloud || hasSpreed) {
      restartUnits = lib.optional hasSpreed "nextcloud-spreed-signaling.service";
    };

    "mail/services" = lib.mkIf hasNextcloud {
      restartUnits = [ "nextcloud-setup.service" ];
    };

    "onlyoffice/jwtSecretFile" = lib.mkIf hasNextcloud {
      restartUnits = lib.optional (
        config.systemd.services ? nextcloud-config-onlyoffice
      ) "nextcloud-config-onlyoffice.service";
    };

    # Matrix / Coturn 全网共享 HMAC 密钥（用于 STUN/TURN 认证）
    "matrix/turn_shared_secret" = {
      mode = "0440";
      group = lib.mkDefault "acme";
    };
  };

  # ── Sops 渲染模板 ──────────────────────────────────────────
  sops.templates = lib.mkMerge [
    (lib.mkIf hasNextcloud {
      "nextcloud-secret-config" = {
        content = builtins.toJSON {
          mail_smtppassword = config.sops.placeholder."mail/services";
          oidc_login_client_secret = config.sops.placeholder."nextcloud/oidc-secret";
          onlyoffice = {
            jwt_secret = config.sops.placeholder."onlyoffice/jwtSecretFile";
          };
        };
        owner = "nextcloud";
        group = "nextcloud";
      };
    })

    (lib.mkIf (hasNextcloud || hasSpreed) {
      "nextcloud-talk-hpb-backend-secret" = {
        content = config.sops.placeholder."nextcloud/turn-secret";
        owner = spreedOwner;
        group = spreedGroup;
        mode = "0400";
      };

      "nextcloud-talk-hpb-internal-secret" = {
        content = config.sops.placeholder."nextcloud/turn-secret";
        owner = spreedOwner;
        group = spreedGroup;
        mode = "0400";
      };

      "nextcloud-talk-hpb-hashkey" = {
        content = config.sops.placeholder."nextcloud/turn-secret";
        owner = spreedOwner;
        group = spreedGroup;
        mode = "0400";
      };

      "nextcloud-talk-hpb-blockkey" = {
        content = config.sops.placeholder."nextcloud/turn-secret";
        owner = spreedOwner;
        group = spreedGroup;
        mode = "0400";
      };
    })
  ];
}
