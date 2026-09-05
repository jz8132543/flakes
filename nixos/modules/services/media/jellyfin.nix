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
      apiKey._secret = config.sops.secrets."media/jellyfin_api_key".path;
      network.baseUrl = "jellyfin";
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

      # 1. 声明式管理 Jellyfin 用户转码权限：
      # - 禁用服务器端视频重编码 (Kind 9)，彻底消除 ffmpeg 占满 CPU 的情况
      # - 允许音频转码 (Kind 8) 与 容器转封装 Remux (Kind 10)，保留良好播放兼容性且几乎不消耗 CPU
      # - 禁用远程强制转码 (Kind 11)、离线同步转码 (Kind 12)、媒体转换 (Kind 13)
      # - 通过 SQLite 触发器确保后续任何新用户（SSO 或手动新建）或权限修改时自动强制生效
      jellyfin-disable-transcoding = {
        description = "声明式管理 Jellyfin 转码权限：禁用视频转码，允许音频转码与容器转封装 (Remux)";
        after = [ "jellyfin.service" ];
        requires = [ "jellyfin.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "jellyfin-transcode-policy" ''
                          DB_FILE="/data/.state/jellyfin/data/jellyfin.db"
                          if [ -f "$DB_FILE" ]; then
                            ${pkgs.sqlite}/bin/sqlite3 "$DB_FILE" << 'EOF'
                            -- 更新所有已有用户权限
                            UPDATE Permissions SET Value = 0 WHERE Kind IN (9, 11, 12, 13);
                            UPDATE Permissions SET Value = 1 WHERE Kind IN (8, 10);

                            -- 建立触发器，针对后续新插入的用户权限自动强制该规则
                            CREATE TRIGGER IF NOT EXISTS trg_transcode_policy_insert
                            AFTER INSERT ON Permissions
                            FOR EACH ROW
                            BEGIN
                              UPDATE Permissions SET Value = 0 WHERE Id = NEW.Id AND NEW.Kind IN (9, 11, 12, 13) AND NEW.Value != 0;
                              UPDATE Permissions SET Value = 1 WHERE Id = NEW.Id AND NEW.Kind IN (8, 10) AND NEW.Value != 1;
                            END;

                            -- 建立触发器，针对后续修改用户权限的操作自动强制该规则
                            CREATE TRIGGER IF NOT EXISTS trg_transcode_policy_update
                            AFTER UPDATE OF Value ON Permissions
                            FOR EACH ROW
                            BEGIN
                              UPDATE Permissions SET Value = 0 WHERE Id = NEW.Id AND NEW.Kind IN (9, 11, 12, 13) AND NEW.Value != 0;
                              UPDATE Permissions SET Value = 1 WHERE Id = NEW.Id AND NEW.Kind IN (8, 10) AND NEW.Value != 1;
                            END;
            EOF
                          fi
          '';
        };
      };

      # 2. 声明式关闭 Jellyfin 快进缩略图 (Trickplay) 与章节图提取：
      # 消除新视频导入时 ffmpeg 以 0.1 fps 全片逐帧解码生成预览图导致的长时间 CPU 100% 满载
      jellyfin-disable-trickplay = {
        description = "声明式关闭 Jellyfin 快进缩略图 (Trickplay) 与章节图提取";
        after = [ "jellyfin.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "jellyfin-disable-trickplay" ''
            ROOT_DIR="/data/.state/jellyfin/root/default"
            if [ -d "$ROOT_DIR" ]; then
              # 遍历所有媒体库的 options.xml 配置文件
              ${pkgs.findutils}/bin/find "$ROOT_DIR" -name "options.xml" | while read -r opt; do
                # 关闭快进缩略图提取 (Trickplay)
                if ${pkgs.gnugrep}/bin/grep -q "<EnableTrickplayImageExtraction>" "$opt"; then
                  ${pkgs.gnused}/bin/sed -i 's|<EnableTrickplayImageExtraction>.*</EnableTrickplayImageExtraction>|<EnableTrickplayImageExtraction>false</EnableTrickplayImageExtraction>|g' "$opt"
                fi
                # 关闭扫库时提取章节图像
                if ${pkgs.gnugrep}/bin/grep -q "<ExtractChapterImagesDuringLibraryScan>" "$opt"; then
                  ${pkgs.gnused}/bin/sed -i 's|<ExtractChapterImagesDuringLibraryScan>.*</ExtractChapterImagesDuringLibraryScan>|<ExtractChapterImagesDuringLibraryScan>false</ExtractChapterImagesDuringLibraryScan>|g' "$opt"
                fi
                # 关闭章节图像提取
                if ${pkgs.gnugrep}/bin/grep -q "<EnableChapterImageExtraction>" "$opt"; then
                  ${pkgs.gnused}/bin/sed -i 's|<EnableChapterImageExtraction>.*</EnableChapterImageExtraction>|<EnableChapterImageExtraction>false</EnableChapterImageExtraction>|g' "$opt"
                fi
                # 将 Trickplay 扫描行为设为 Non (从不提取)
                if ${pkgs.gnugrep}/bin/grep -q "<ScanBehavior>" "$opt"; then
                  ${pkgs.gnused}/bin/sed -i 's|<ScanBehavior>.*</ScanBehavior>|<ScanBehavior>Non</ScanBehavior>|g' "$opt"
                fi
              done
            fi

            # 如果后台当前有运行中的 Trickplay ffmpeg 提取进程（以 fps=0.1 识别），立即终止以释放 CPU
            ${pkgs.procps}/bin/pkill -f "jellyfin-ffmpeg.*fps=0.1" || true
          '';
        };
      };

      # 3. 创建 Jellyfin 默认用户策略模板（供 SSO 等插件使用）
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
                  <!-- 策略：禁用视频转码，允许音频转码与容器转封装 (Remux) -->
                  <EnableAudioPlaybackTranscoding>true</EnableAudioPlaybackTranscoding>
                  <EnableVideoPlaybackTranscoding>false</EnableVideoPlaybackTranscoding>
                  <EnablePlaybackRemuxing>true</EnablePlaybackRemuxing>
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
              cat > /data/.state/jellyfin/plugins/configurations/SSO-Auth.xml <<EOF
              ${ssoConfig}
              EOF
              chown -R jellyfin:media /data/.state/jellyfin/plugins/configurations/SSO-Auth.xml
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
            # "IntroSkipper" = pkgs.jellyfin-plugins.intro-skipper;
            # "Jellyfin.Plugin.PlaybackReporting" = pkgs.jellyfin-plugins.playback-reporting;
            # "Jellyfin.Plugin.Bangumi" = pkgs.jellyfin-plugins.bangumi;
            # "Shokofin" = pkgs.jellyfin-plugins.shokofin;
            # "AniSync" = pkgs.jellyfin-plugins.ani-sync;
            # "Jellyfin.Plugin.Bazarr" = pkgs.jellyfin-plugins.bazarr;
            # "Jellyfin.Plugin.MergeVersions" = pkgs.jellyfin-plugins.merge-versions;
            # "Jellyfin.Plugin.SkinManager" = pkgs.jellyfin-plugins.skin-manager;
            # "MetaTube" = pkgs.jellyfin-plugins.metatube;
            # "Jellyfin.Plugin.TMDbBoxSets" = pkgs.jellyfin-plugins.tmdb-box-sets;
            # "Jellyfin.Plugin.Douban" = pkgs.jellyfin-plugins.douban;
            # "Jellyfin.Plugin.Fanart" = pkgs.jellyfin-plugins.fanart;
            # "Jellyfin.Plugin.SSO" = pkgs.jellyfin-plugins.sso;
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
