{
  config,
  lib,
  inputs,
  ...
}:

let
  cfg = config.desktop.winapps;
in
{
  config = lib.mkIf (cfg.podman.enable || cfg.docker.enable) {
    environment.etc = {
      "winapps/oem/RDPApps.reg".source = "${inputs.winapps}/oem/RDPApps.reg";
      "winapps/oem/Container.reg".source = "${inputs.winapps}/oem/Container.reg";
      "winapps/oem/NetProfileCleanup.ps1".source = "${inputs.winapps}/oem/NetProfileCleanup.ps1";
      "winapps/oem/TimeSync.ps1".source = "${inputs.winapps}/oem/TimeSync.ps1";
      "winapps/oem/install.bat".text = ''
        @echo off
        echo ====================================================
        echo [NixOS-WinApps] Initializing Unattended Environment
        echo ====================================================

        :: 1. 导入 WinApps 官方注册表配置 (RDPApps.reg 与 Container.reg)
        if exist "%~dp0RDPApps.reg" (
            echo [INFO] Importing RDPApps.reg...
            reg import "%~dp0RDPApps.reg" >nul 2>&1
        )
        if exist "%~dp0Container.reg" (
            echo [INFO] Importing Container.reg...
            reg import "%~dp0Container.reg" >nul 2>&1
        )

        :: 2. 启用远程桌面防火墙规则
        echo [INFO] Configuring Remote Desktop firewall rules...
        netsh advfirewall firewall set rule group="remote desktop" new enable=Yes >nul 2>&1
        powershell -NoProfile -ExecutionPolicy Bypass -Command "if (Get-Command Enable-NetFirewallRule -ErrorAction SilentlyContinue) { Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' }" >nul 2>&1

        :: 3. 彻底禁用自动更新与遥测
        echo [INFO] Disabling Windows update and telemetry services...
        sc stop wuauserv >nul 2>&1
        sc config wuauserv start= disabled >nul 2>&1
        sc stop bits >nul 2>&1
        sc config bits start= disabled >nul 2>&1
        sc stop DiagTrack >nul 2>&1
        sc config DiagTrack start= disabled >nul 2>&1

        :: 4. 解决 tsclient 受保护视图与黄色只读警告栏
        :: 将 tsclient 域名添加到本地 Intranet (Zone 1)
        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\tsclient" /f >nul 2>&1
        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\tsclient" /v file /t REG_DWORD /d 1 /f >nul 2>&1
        reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\tsclient" /f >nul 2>&1
        reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\tsclient" /v file /t REG_DWORD /d 1 /f >nul 2>&1

        :: 允许 Office 从网络位置信任文档 (Office 2016 / 2019 / 2021 / 365)
        reg add "HKCU\Software\Microsoft\Office\16.0\Word\Security\Trusted Locations" /v AllowNetworkLocations /t REG_DWORD /d 1 /f >nul 2>&1
        reg add "HKCU\Software\Microsoft\Office\16.0\Excel\Security\Trusted Locations" /v AllowNetworkLocations /t REG_DWORD /d 1 /f >nul 2>&1
        reg add "HKCU\Software\Microsoft\Office\16.0\PowerPoint\Security\Trusted Locations" /v AllowNetworkLocations /t REG_DWORD /d 1 /f >nul 2>&1

        :: 5. 复制并注册网络清理与时间同步任务
        if exist "%~dp0NetProfileCleanup.ps1" (
            copy /Y "%~dp0NetProfileCleanup.ps1" "%windir%\" >nul
            schtasks /create /tn "WinApps_NetworkProfileCleanup" /tr "powershell.exe -ExecutionPolicy Bypass -File \"%windir%\NetProfileCleanup.ps1\"" /sc onstart /ru "SYSTEM" /rl HIGHEST /f >nul 2>&1
        )
        if exist "%~dp0TimeSync.ps1" (
            copy /Y "%~dp0TimeSync.ps1" "%windir%\" >nul
            schtasks /create /tn "TimeSync" /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File \"%windir%\TimeSync.ps1\"" /sc onlogon /rl HIGHEST /f >nul 2>&1
        )

        :: 6. Install Office from a licensed Office Deployment Tool package in dockur's Data share.
        :: The share is available as \\host.lan\Data; tsclient only exists during an RDP session.
        set "OFFICE_SHARE=\\host.lan\Data"
        if exist "Z:\setup.exe" set "OFFICE_SHARE=Z:"
        if exist "%OFFICE_SHARE%\setup.exe" if exist "%OFFICE_SHARE%\configuration.xml" (
            if not exist "%ProgramFiles%\Microsoft Office\root\Office16\WINWORD.EXE" (
                echo [INFO] Installing Office using the supplied deployment configuration...
                "%OFFICE_SHARE%\setup.exe" /configure "%OFFICE_SHARE%\configuration.xml"
            )
        ) else (
            echo [WARN] Office not installed: provide licensed Office Deployment Tool setup.exe and configuration.xml in WinAppsShare.
        )

        :: Office Click-to-Run installs under root\Office16; WinApps' legacy app definitions
        :: expect Office16 directly under Microsoft Office. Create the junction if needed.
        if exist "%ProgramFiles%\Microsoft Office\root\Office16\WINWORD.EXE" (
            if not exist "%ProgramFiles%\Microsoft Office\Office16\WINWORD.EXE" (
                mklink /J "%ProgramFiles%\Microsoft Office\Office16" "%ProgramFiles%\Microsoft Office\root\Office16"
            )
        )

        echo [NixOS-WinApps] Provisioning completed successfully.
      '';
    };
  };
}
