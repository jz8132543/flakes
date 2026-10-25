{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.programs.winpodx;
  guard = pkgs.writeShellScriptBin "podman" (
    builtins.replaceStrings [ "@podman@" ] [ "${pkgs.podman}/bin/podman" ] (
      builtins.readFile ./podman-guard.sh
    )
  );
  officeXml =
    if cfg.office.configurationFile != null then
      cfg.office.configurationFile
    else
      pkgs.writeText "office-configuration.xml" ''
        <Configuration>
          <Add OfficeClientEdition="64" Channel="${lib.escapeXML cfg.office.channel}">
            <Product ID="${lib.escapeXML cfg.office.productId}">
              <Language ID="${lib.escapeXML cfg.office.language}" />
            </Product>
          </Add>
          <Property Name="SharedComputerLicensing" Value="0" />
          <Updates Enabled="TRUE" />
          <RemoveMSI />
          <Display Level="None" AcceptEULA="TRUE" />
        </Configuration>
      '';
  settings = {
    officeEnabled = cfg.office.enable;
    activationMethod = cfg.activation.method;
    requireActivation = cfg.activation.requireActivation;
    masSha256 = "850f979665fb93999acae93f4790c1ff8ed2041532060b7966a121c2d29a0bfa";
  };
  generation = builtins.hashString "sha256" (
    builtins.toJSON settings
    + builtins.readFile ./office.ps1
    + (
      if cfg.office.configurationFile == null then
        cfg.office.productId + cfg.office.channel + cfg.office.language
      else
        builtins.readFile cfg.office.configurationFile
    )
  );
  deploymentSettings = pkgs.writeText "deployment-settings.json" (
    builtins.toJSON (settings // { inherit generation; })
  );
  mas = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/massgravel/Microsoft-Activation-Scripts/40c74d0d7f42146b1dd1ab59b5c7e836d6a56d1f/MAS/All-In-One-Version-KL/MAS_AIO.cmd";
    hash = "sha256-hQ+XlmX7k5mayuk/R5DB/47SBBUyBgt5ZqEhwtKaC/o=";
    name = "MAS_AIO-3.12.cmd";
  };
  base = inputs.winpodx.packages.${pkgs.stdenv.hostPlatform.system}.winpodx;
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.backend == "podman" || !cfg.initialDeployment.enable;
        message = "Protected automatic first deployment currently requires the Podman backend.";
      }
    ];
    programs.winpodx.package = lib.mkDefault (
      base.overridePythonAttrs (old: {
        doCheck = false;
        dependencies =
          old.dependencies
          ++ (with pkgs.python3Packages; [
            pillow
            cairosvg
            pyxdg
          ]);
        postPatch =
          (old.postPatch or "")
          + ''
            substituteInPlace src/winpodx/cli/app.py \
              --replace-fail 'def _register_desktop_entries(discovered) -> None:' \
              $'def _register_desktop_entries(discovered) -> None:\n    import os\n    if os.environ.get("WINPODX_DECLARATIVE_SHORTCUTS") == "1":\n        return'
            substituteInPlace src/winpodx/desktop/tray_spawn.py \
              --replace-fail 'log = logging.getLogger(__name__)' \
              $'log = logging.getLogger(__name__)\n\ndef _deployment_check():\n    subprocess.run(["${guard}/bin/podman", "check"], check=True)' \
              --replace-fail '    marker = Path(xdg) / "winpodx" / ".install_in_progress"' \
              $'    if (Path(xdg) / "winpodx" / "deployment.pending").exists():\n        return True\n    marker = Path(xdg) / "winpodx" / ".install_in_progress"'
            substituteInPlace src/winpodx/core/daemon.py \
              --replace-fail '        sessions = list_active_sessions()' \
              $'        from winpodx.desktop.tray_spawn import _install_in_progress\n        if _install_in_progress():\n            idle_since = None\n            stop_event.wait(30)\n            continue\n        sessions = list_active_sessions()'
            substituteInPlace src/winpodx/core/pod/lifecycle.py \
              --replace-fail 'def stop_pod(cfg: Config) -> PodStatus:' \
              $'def stop_pod(cfg: Config) -> PodStatus:\n    from winpodx.desktop.tray_spawn import _deployment_check\n    _deployment_check()'
            substituteInPlace src/winpodx/cli/setup_cmd.py \
              --replace-fail 'def _recreate_container(cfg: Config) -> None:' \
              $'def _recreate_container(cfg: Config) -> None:\n    from winpodx.desktop.tray_spawn import _deployment_check\n    _deployment_check()'
            substituteInPlace src/winpodx/cli/pod.py \
              --replace-fail '    raw_storage = (cfg.pod.storage_path or "").strip()' \
              $'    from winpodx.desktop.tray_spawn import _deployment_check\n    _deployment_check()\n    raw_storage = (cfg.pod.storage_path or "").strip()'
            substituteInPlace src/winpodx/core/storage_migration.py \
              --replace-fail '    from winpodx.core.compose import generate_compose' \
              $'    from winpodx.core.compose import generate_compose\n    from winpodx.desktop.tray_spawn import _deployment_check\n    _deployment_check()'
            substituteInPlace src/winpodx/backend/podman.py \
              --replace-fail '    def start(self) -> None:' \
              $'    def start(self) -> None:\n        from winpodx.desktop.tray_spawn import _install_in_progress\n        flags = ["--no-recreate"] if _install_in_progress() else []' \
              --replace-fail '[*self._compose_cmd(), "up", "-d"],' \
              '[*self._compose_cmd(), "up", "-d", *flags],'
          ''
          + lib.optionalString cfg.initialDeployment.enable ''
            cp ${./office.ps1} config/oem/nixos-office.ps1
            cp ${./bootstrap.ps1} config/oem/nixos-bootstrap.ps1
            cp ${officeXml} config/oem/office-configuration.xml
            cp ${deploymentSettings} config/oem/deployment-settings.json
            ${lib.optionalString (cfg.activation.method == "mas") "cp ${mas} config/oem/MAS_AIO.cmd"}
            substituteInPlace config/oem/install.bat \
              --replace-fail 'REM Sentinel lives under' \
              $'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\\OEM\\nixos-bootstrap.ps1\r\nif errorlevel 1 exit /b 1\r\nREM Sentinel lives under'
          '';
        makeWrapperArgs = (old.makeWrapperArgs or [ ]) ++ [
          "--prefix"
          "PATH"
          ":"
          "${lib.makeBinPath [
            guard
            pkgs.util-linux
            pkgs.coreutils
          ]}"
          "--set-default"
          "WINPODX_DECLARATIVE_SHORTCUTS"
          "1"
        ];
      })
    );
  };
}
