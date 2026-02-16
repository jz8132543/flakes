{
  lib,
  pkgs,
  config,
  ...
}:
{
  config = {
    nixflix.jellyfin = {
      enable = true;
      users = {
        i = {
          mutable = false;
          policy.isAdministrator = true;
          password = {
            _secret = config.sops.secrets."password".path;
          };
        };
      };
    };

    systemd.services = {
      jellyfin.serviceConfig = {
        PrivateUsers = lib.mkForce false;
        UMask = "0002";
        Environment = "LANG=zh_CN.UTF-8";
      };

      jellyfin-disable-transcoding = {
        description = "Globally disable Jellyfin transcoding";
        after = [ "jellyfin.service" ];
        requires = [ "jellyfin.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.sqlite}/bin/sqlite3 /data/.state/jellyfin/data/jellyfin.db \"UPDATE Permissions SET Value = 0 WHERE Kind IN (9, 10);\"";
        };
      };

      jellyfin-default-policy = {
        description = "Create Jellyfin default user policy template";
        before = [ "jellyfin.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart =
            let
              policyContent = ''
                <UserPolicy xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
                  <IsAdministrator>false</IsAdministrator>
                  <IsHidden>false</IsHidden>
                  <IsDisabled>false</IsDisabled>
                  <MaxParentalRating>0</MaxParentalRating>
                  <BlockedTags />
                  <EnableUserPreferenceAccess>true</EnableUserPreferenceAccess>
                  <AccessSchedules />
                  <BlockUnratedItems />
                  <EnableRemoteControlOfOtherUsers>false</EnableRemoteControlOfOtherUsers>
                  <EnableSharedDeviceControl>true</EnableSharedDeviceControl>
                  <EnableRemoteAccess>true</EnableRemoteAccess>
                  <EnableLiveTvManagement>false</EnableLiveTvManagement>
                  <EnableLiveTvAccess>true</EnableLiveTvAccess>
                  <EnableMediaPlayback>true</EnableMediaPlayback>
                  <EnableAudioPlaybackTranscoding>false</EnableAudioPlaybackTranscoding>
                  <EnableVideoPlaybackTranscoding>false</EnableVideoPlaybackTranscoding>
                  <EnablePlaybackRemuxing>false</EnablePlaybackRemuxing>
                  <ForceRemoteSourceTranscoding>false</ForceRemoteSourceTranscoding>
                  <EnableContentDownloading>true</EnableContentDownloading>
                  <EnableSyncTranscoding>false</EnableSyncTranscoding>
                  <EnableMediaConversion>false</EnableMediaConversion>
                  <EnabledDevices />
                  <EnableAllDevices>true</EnableAllDevices>
                  <EnabledChannels />
                  <EnableAllChannels>true</EnableAllChannels>
                  <EnabledFolders />
                  <EnableAllFolders>true</EnableAllFolders>
                  <InvalidLoginAttemptCount>0</InvalidLoginAttemptCount>
                  <LoginAttemptsBeforeLockout>0</LoginAttemptsBeforeLockout>
                  <MaxActiveSessions>0</MaxActiveSessions>
                  <EnablePublicSharing>true</EnablePublicSharing>
                  <BlockedMediaFolders />
                  <BlockedChannels />
                  <RemoteClientBitrateLimit>0</RemoteClientBitrateLimit>
                  <AuthenticationProviderId>Jellyfin.Server.Implementations.Users.DefaultAuthenticationProvider</AuthenticationProviderId>
                  <PasswordResetProviderId>Jellyfin.Server.Implementations.Users.DefaultPasswordResetProvider</PasswordResetProviderId>
                  <SyncPlayAccess>CreateAndJoinGroups</SyncPlayAccess>
                </UserPolicy>
              '';
            in
            pkgs.writeShellScript "create-jellyfin-policy" ''
              mkdir -p /data/.state/jellyfin/config
              cat > /data/.state/jellyfin/config/default_policy.xml <<EOF
              ${policyContent}
              EOF
              chown -R jellyfin:media /data/.state/jellyfin/config/default_policy.xml
            '';
        };
      };

      jellyfin-sso-config = {
        description = "Configure Jellyfin SSO plugin";
        before = [ "jellyfin.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart =
            let
              ssoConfig = ''
                <?xml version="1.0" encoding="utf-8"?>
                <PluginConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
                  <SsoConfigurations>
                    <SsoConfiguration>
                      <SsoProviderName>Keycloak</SsoProviderName>
                      <OidcClientId>jellyfin</OidcClientId>
                      <OidcClientSecret>${config.sops.placeholder."jellyfin/oidc_client_secret"}</OidcClientSecret>
                      <OidcAuthority>https://sso.dora.im/realms/users</OidcAuthority>
                      <OidcScopes>
                        <string>openid</string>
                        <string>profile</string>
                        <string>email</string>
                      </OidcScopes>
                      <AdminRoles>
                        <string>admin</string>
                      </AdminRoles>
                    </SsoConfiguration>
                  </SsoConfigurations>
                </PluginConfiguration>
              '';
            in
            pkgs.writeShellScript "jellyfin-sso-config" ''
              mkdir -p /data/.state/jellyfin/plugins/configurations
              cat > /data/.state/jellyfin/plugins/configurations/Jellyfin.Plugin.SSO.xml <<EOF
              ${ssoConfig}
              EOF
              chown -R jellyfin:media /data/.state/jellyfin/plugins/configurations/Jellyfin.Plugin.SSO.xml
            '';
        };
      };
    };

    system.activationScripts.jellyfin-plugins = {
      deps = [
        "users"
        "groups"
      ];
      text =
        let
          inherit (config.services.jellyfin) user;
          group = "media";
          dataDir = "${config.nixflix.stateDir}/jellyfin";
          pluginDir = "${dataDir}/plugins";

          jellyfinPlugins = {
            "IntroSkipper" = pkgs.jellyfin-plugins.intro-skipper;
            "Jellyfin.Plugin.PlaybackReporting" = pkgs.jellyfin-plugins.playback-reporting;
            "Jellyfin.Plugin.Bangumi" = pkgs.jellyfin-plugins.bangumi;
            "Shokofin" = pkgs.jellyfin-plugins.shokofin;
            "AniSync" = pkgs.jellyfin-plugins.ani-sync;
            "Jellyfin.Plugin.Bazarr" = pkgs.jellyfin-plugins.bazarr;
            "Jellyfin.Plugin.MergeVersions" = pkgs.jellyfin-plugins.merge-versions;
            "Jellyfin.Plugin.SkinManager" = pkgs.jellyfin-plugins.skin-manager;
            "MetaTube" = pkgs.jellyfin-plugins.metatube;
            "Jellyfin.Plugin.TMDbBoxSets" = pkgs.jellyfin-plugins.tmdb-box-sets;
            "Jellyfin.Plugin.Douban" = pkgs.jellyfin-plugins.douban;
            "Jellyfin.Plugin.Fanart" = pkgs.jellyfin-plugins.fanart;
            "Jellyfin.Plugin.SSO" = pkgs.jellyfin-plugins.sso;
          };

          mkSync = name: path: ''
            mkdir -p "${pluginDir}/${name}"
            # Use rsync if available for efficiency, or just cp
            # We use -L to follow symlinks from the store if any
            ${pkgs.rsync}/bin/rsync -aqL --delete "${path}/" "${pluginDir}/${name}/"
            # Explicitly set permissions to be writable by owner
            find "${pluginDir}/${name}" -type d -exec chmod 0755 {} +
            find "${pluginDir}/${name}" -type f -exec chmod 0644 {} +
          '';
        in
        ''
          mkdir -p "${pluginDir}"
          chown ${user}:${group} "${pluginDir}"
          chmod 0755 "${pluginDir}"

          # Clean up old symlinks that might exist from previous configuration
          find "${pluginDir}" -maxdepth 1 -type l -delete

          ${lib.concatStringsSep "\n" (lib.mapAttrsToList mkSync jellyfinPlugins)}

          chown -R ${user}:${group} "${pluginDir}"
        '';
    };
  };
}
