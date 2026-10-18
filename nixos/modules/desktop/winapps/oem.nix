{ config, lib, ... }:

let
  cfg = config.desktop.winapps;
in
{
  config = lib.mkIf (cfg.podman.enable || cfg.docker.enable) {
    environment.etc."winapps/oem/install.bat".text = ''
      @echo off
      echo ====================================================
      echo [NixOS-WinApps] Initializing Unattended Environment
      echo ====================================================

      :: 1. 彻底禁用自动更新与遥测
      sc stop wuauserv
      sc config wuauserv start= disabled
      sc stop bits
      sc config bits start= disabled
      sc stop DiagTrack
      sc config DiagTrack start= disabled

      :: 2. 启用 RemoteApp 完整白名单
      reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList" /v fDisabledAllowList /t REG_DWORD /d 1 /f

      :: 3. 解决 tsclient 受保护视图与黄色只读警告栏
      :: 将 tsclient 域名添加到本地 Intranet (Zone 1)
      reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\tsclient" /f
      reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\tsclient" /v file /t REG_DWORD /d 1 /f
      reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\tsclient" /f
      reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\tsclient" /v file /t REG_DWORD /d 1 /f

      :: 允许 Office 从网络位置信任文档 (Office 2016 / 2019 / 2021 / 365)
      reg add "HKCU\Software\Microsoft\Office\16.0\Word\Security\Trusted Locations" /v AllowNetworkLocations /t REG_DWORD /d 1 /f
      reg add "HKCU\Software\Microsoft\Office\16.0\Excel\Security\Trusted Locations" /v AllowNetworkLocations /t REG_DWORD /d 1 /f
      reg add "HKCU\Software\Microsoft\Office\16.0\PowerPoint\Security\Trusted Locations" /v AllowNetworkLocations /t REG_DWORD /d 1 /f

      echo [NixOS-WinApps] Provisioning completed successfully.
    '';
  };
}
