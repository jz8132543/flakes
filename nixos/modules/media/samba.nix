{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.services.media-samba;
in
{
  options.services.media-samba = {
    enable = mkEnableOption "Media Samba Share";
    path = mkOption {
      type = types.path;
      default = "/var/lib/media";
      description = "Path to share";
    };
  };

  config = mkIf cfg.enable {
    services.samba = {
      enable = true;
      openFirewall = true;
      settings = {
        global = {
          "workgroup" = "WORKGROUP";
          "server string" = "NixOS Media";
          "netbios name" = "nixos";
          "security" = "user";
          "hosts allow" = "192.168. 127.0.0.1 localhost 10. 100.";
          "hosts deny" = "0.0.0.0/0";
          "guest account" = "nobody";
          "map to guest" = "bad user";

          # Apple Optimization
          "vfs objects" = "catia fruit streams_xattr";
          "fruit:metadata" = "stream";
          "fruit:model" = "MacSamba";
          "fruit:posix_rename" = "yes";
          "fruit:veto_appledouble" = "no";
          "fruit:nfs_aces" = "no";
          "fruit:wipe_intentionally_left_blank_rfork" = "yes";
          "fruit:delete_empty_adfiles" = "yes";
        };
        "media" = {
          "path" = cfg.path;
          "browseable" = "yes";
          "read only" = "no";
          "guest ok" = "yes";
          "create mask" = "0644";
          "directory mask" = "0755";
          "force user" = "media";
          "force group" = "media";
        };
      };
    };

    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        userServices = true;
      };
      extraServiceFiles = {
        smb = ''
          <?xml version="1.0" standalone='no'?><!--*-nxml-*-->
          <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
          <service-group>
            <name replace-wildcards="yes">%h</name>
            <service>
              <type>_smb._tcp</type>
              <port>445</port>
            </service>
            <service>
              <type>_device-info._tcp</type>
              <port>0</port>
              <txt-record>model=MacPro7,1@ECOLOR=226,226,224</txt-record>
            </service>
          </service-group>
        '';
      };
    };

    # Ensure media user/group exists and has permissions
    users.groups.media = { };
    users.users.media = {
      isSystemUser = true;
      group = "media";
      createHome = true;
      home = cfg.path;
      description = "Media Server User";
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.path} 0775 media media -"
      "d ${cfg.path}/movies 0775 media media -"
      "d ${cfg.path}/tv 0775 media media -"
      "d ${cfg.path}/downloads 0775 media media -"
    ];
  };
}
