{
  config,
  lib,
  nixosModules,
  ...
}: let
  mkKeyVal = opt: val: ["-o" (opt + "=" + val)];
  mkOpts = opts: lib.concatLists (lib.mapAttrsToList mkKeyVal opts);
in {
  imports = [nixosModules.services.acme];
  networking.firewall.allowedTCPPorts = [25 465 993];
  sops.secrets = {
    "mail/ldap" = {};
    dkim = {
      owner = "rspamd";
      path = "/var/lib/rspamd/dkim.key";
    };
  };

  sops.templates."postfix-sender-maps" = {
    content = ''
      server_host = ${config.lib.self.data.ldap}
      version = 3
      bind = yes
      bind_dn = uid=mail,ou=people,dc=dora,dc=im
      bind_pw = ${config.sops.placeholder."mail/ldap"}
      search_base = ou=people,dc=dora,dc=im
      query_filter = (mail=%s)
      result_attribute = uid
      domain = dora.im
      result_format = %s@dora.im
    '';
  };

  services.postfix = {
    enable = true;
    hostname = config.networking.fqdn;
    config = {
      smtpd_use_tls = "yes";
      smtp_tls_note_starttls_offer = "yes";
      smtpd_tls_security_level = "may";
      smtpd_tls_auth_only = "yes";
      smtp_dns_support_level = "dnssec";
      smtp_tls_security_level = "dane";
      smtpd_tls_cert_file = "${config.security.acme.certs."main".directory}/full.pem";
      smtpd_tls_key_file = "${config.security.acme.certs."main".directory}/key.pem";
      smtpd_tls_CAfile = "${config.security.acme.certs."main".directory}/fullchain.pem";
      smtpd_tls_dh512_param_file = config.security.dhparams.params.postfix512.path;
      smtpd_tls_dh1024_param_file = config.security.dhparams.params.postfix2048.path;
      smtpd_tls_session_cache_database = ''btree:''${data_directory}/smtpd_scache'';
      smtpd_tls_mandatory_protocols = "!SSLv2,!SSLv3,!TLSv1,!TLSv1.1";
      smtpd_tls_protocols = "!SSLv2,!SSLv3,!TLSv1,!TLSv1.1";
      smtpd_tls_mandatory_ciphers = "medium";
      tls_medium_cipherlist = "AES128+EECDH:AES128+EDH";

      smtpd_relay_restrictions = ["permit_sasl_authenticated" "defer_unauth_destination"];
      virtual_transport = "lmtp:unix:/run/dovecot2/lmtp";
      virtual_mailbox_domains = ["dora.im"];

      lmtp_destination_recipient_limit = "1";
      recipient_delimiter = "+";
      disable_vrfy_command = true;

      milter_default_action = "accept";
      smtpd_milters = ["unix:/run/rspamd/postfix.sock"];
      non_smtpd_milters = ["unix:/run/rspamd/postfix.sock"];
      internal_mail_filter_classes = ["bounce"];
    };
    masterConfig = {
      lmtp = {
        args = ["flags=O"];
      };
      "465" = {
        type = "inet";
        private = false;
        command = "smtpd";
        args = mkOpts {
          smtpd_tls_security_level = "none";
          smtpd_tls_wrappermode = "yes";
          smtpd_sasl_auth_enable = "yes";
          broken_sasl_auth_clients = "yes";
          smtpd_sasl_type = "dovecot";
          smtpd_sasl_path = "/run/dovecot2/auth-postfix";
          smtpd_sender_login_maps = "ldap:${config.sops.templates."postfix-sender-maps".path}";
          # local_recipient_maps = "ldap:${ldapSenderMap}";
          smtpd_client_restrictions = "permit_sasl_authenticated,reject";
          smtpd_sender_restrictions = "reject_sender_login_mismatch";
          smtpd_recipient_restrictions = "reject_non_fqdn_recipient,reject_unknown_recipient_domain,permit_sasl_authenticated,reject";
        };
      };
    };
  };

  services.rspamd = {
    enable = true;
    workers = {
      controller = {
        bindSockets = ["localhost:11334"];
      };
      rspamd_proxy = {
        bindSockets = [
          {
            mode = "0666";
            socket = "/run/rspamd/postfix.sock";
          }
        ];
      };
    };
    locals = {
      "worker-controller.inc".text = ''
        secure_ip = ["127.0.0.1", "::1"];
      '';
      "worker-proxy.inc".text = ''
        upstream "local" {
          self_scan = yes;
        }
      '';
      "redis.conf".text = ''
        servers = "127.0.0.1:${toString config.services.redis.servers.rspamd.port}";
      '';
      "classifier-bayes.conf".text = ''
        autolearn = true;
      '';
      "dkim_signing.conf".text = ''
        path = "${config.sops.secrets.dkim.path}";
        selector = "default";
        allow_username_mismatch = true;
        allow_envfrom_empty = true;
      '';
    };
  };

  services.telegraf.extraConfig.inputs = {
    prometheus.urls = ["http://localhost:11334/metrics"];
  };

  boot.kernel.sysctl."vm.overcommit_memory" = lib.mkForce 1;

  services.redis.servers.rspamd = {
    enable = true;
    port = 16380;
  };
  security.dhparams = {
    enable = true;
    params.postfix512.bits = 512;
    params.postfix2048.bits = 1024;
  };
}
