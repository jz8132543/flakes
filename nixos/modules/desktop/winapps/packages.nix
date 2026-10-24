{
  pkgs,
  inputs,
  config,
  lib,
  ...
}:

let
  cfg = config.programs.winapps;
  system = pkgs.stdenv.hostPlatform.system;
  winappsBase = inputs.winapps.packages.${system}.winapps;
  discoverUserApps = pkgs.writeText "discover-user-apps.ps1" ''
    # Upstream scans HKLM App Paths, UWP, Chocolatey and Scoop. Per-user
    # installers such as Doubao often register only HKCU or a Start Menu link.
    $userApps = @{}
    $paths = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\*' -ErrorAction SilentlyContinue |
        ForEach-Object { $_.'(default)' }
    foreach ($path in $paths) {
        $path = $path -replace '^"*|"*$', [string]::Empty
        if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) {
            $userApps[$path] = GetApplicationName -exePath $path
        }
    }
    $shell = New-Object -ComObject WScript.Shell
    $menus = @(
        [Environment]::GetFolderPath('StartMenu'),
        [Environment]::GetFolderPath('CommonStartMenu')
    )
    foreach ($menu in $menus) {
        Get-ChildItem -LiteralPath $menu -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $shortcut = $shell.CreateShortcut($_.FullName)
            $path = [Environment]::ExpandEnvironmentVariables($shortcut.TargetPath)
            # Arguments cannot be represented by upstream's executable-only app
            # metadata. Leave those shortcuts for interactive configuration.
            if ($path -match '\.exe$' -and -not $shortcut.Arguments -and
                $path -notmatch '(?i)(uninstall|unins\d*|update|setup)\.exe$' -and
                (Test-Path -LiteralPath $path -PathType Leaf)) {
                $userApps[$path] = $_.BaseName
            }
        }
    }
    foreach ($path in ($userApps.Keys | Sort-Object)) {
        # ExtractPrograms.ps1 emits Bash array assignments. Reject metacharacters
        # instead of allowing application metadata to become shell commands.
        $name = $userApps[$path] -replace '["`$\\\r\n]', [string]::Empty
        if ($path -notmatch '["`$\r\n]') {
            PrintArrayData -Names @($name) -Paths @($path) -Source 'user'
        }
    }
  '';

  # Keep upstream's installer and client. Only extend its unattended discovery
  # mode and PATH for NixOS services; normal interactive setup is unchanged.
  winappsPackage = winappsBase.overrideAttrs (old: {
    buildInputs = (old.buildInputs or [ ]) ++ [
      pkgs.podman-compose
      pkgs.slirp4netns
    ];
    postPatch = (old.postPatch or "") + ''
      substituteInPlace bin/winapps \
        --replace-fail 'readonly SYS_APP_PATH="/usr/local/share/winapps"' "readonly SYS_APP_PATH=\"$out/src\""
      substituteInPlace setup.sh \
        --replace-fail 'inqMenu "How would you like to handle officially supported applications?" OPTIONS APP_INSTALL' \
          'if [[ "''${WINAPPS_AUTO_DISCOVERY:-0}" == "1" ]]; then APP_INSTALL="Set up all detected officially supported applications"; else inqMenu "How would you like to handle officially supported applications?" OPTIONS APP_INSTALL; fi' \
        --replace-fail 'inqMenu "How would you like to handle other detected applications?" OPTIONS APP_INSTALL' \
          'if [[ "''${WINAPPS_AUTO_DISCOVERY:-0}" == "1" ]]; then APP_INSTALL="Set up all detected applications"; else inqMenu "How would you like to handle other detected applications?" OPTIONS APP_INSTALL; fi'
      cat ${discoverUserApps} >> install/ExtractPrograms.ps1
    '';
  });
in
{
  options.programs.winapps.package = lib.mkOption {
    type = lib.types.package;
    default = winappsPackage;
    description = "Official WinApps Nix package with optional unattended user-application discovery.";
  };

  config = lib.mkIf (cfg.kvm.enable || cfg.docker.enable || cfg.podman.enable) {
    environment.systemPackages =
      with pkgs;
      [
        # Virtual Machine Manager GUI
        virt-manager
        # FreeRDP is required by WinApps to connect to the VM seamlessly
        freerdp
        # WinApps uses podman-compose to manage the container lifecycle (incl. AUTOPAUSE)
        podman-compose
        # User-mode networking for rootless Podman (resilient against complex host route tables like DN42/BGP)
        slirp4netns
        # WinApps package from the community flake
        cfg.package
        inputs.winapps.packages.${system}.winapps-launcher
      ]
      ++ lib.optionals cfg.kvm.enable [
        # Dependencies for KVM dynamic disk discovery script
        os-prober
        util-linux
      ];
  };
}
