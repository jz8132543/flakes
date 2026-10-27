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
        # buildPythonApplication does not run stdenv's installCheckPhase.
        postFixup = (old.postFixup or "") + ''
          (
            export QT_QPA_PLATFORM=offscreen
            export PYTHONDONTWRITEBYTECODE=1
            export PYTHONPATH="$out/${pkgs.python3.sitePackages}:$PYTHONPATH"
            timeout 60 ${pkgs.python3.interpreter} ${./test-refresh.py} -v
          )
        '';
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
            # PySide6 does not register these ordinary-mixin slots on the real
            # window. Explicit QObject slots keep refresh UI work on its thread.
            substituteInPlace src/winpodx/gui/main_window.py \
              --replace-fail 'from PySide6.QtCore import Qt, QThread, QTimer, Signal' \
              'from PySide6.QtCore import Qt, QThread, QTimer, Signal, Slot' \
              --replace-fail '    def _refresh_dashboard(self) -> None:' \
              $'    @Slot(int)\n    def _on_refresh_succeeded(self, count: int) -> None:\n        super()._on_refresh_succeeded(count)\n\n    @Slot(str, str)\n    def _on_refresh_failed(self, kind: str, detail: str) -> None:\n        super()._on_refresh_failed(kind, detail)\n\n    @Slot()\n    def _cleanup_refresh_worker(self) -> None:\n        super()._cleanup_refresh_worker()\n\n    def _refresh_dashboard(self) -> None:'
            substituteInPlace src/winpodx/gui/_main_window_apps.py \
              --replace-fail 'from PySide6.QtCore import QThread, QTimer, Slot' \
              'from PySide6.QtCore import Qt, QThread, QTimer, Slot' \
              --replace-fail 'worker.succeeded.connect(self._on_refresh_succeeded)' \
              'worker.succeeded.connect(self._on_refresh_succeeded, Qt.ConnectionType.QueuedConnection)' \
              --replace-fail 'worker.failed.connect(self._on_refresh_failed)' \
              'worker.failed.connect(self._on_refresh_failed, Qt.ConnectionType.QueuedConnection)' \
              --replace-fail 'thread.finished.connect(self._cleanup_refresh_worker)' \
              'thread.finished.connect(self._cleanup_refresh_worker, Qt.ConnectionType.QueuedConnection)' \
              --replace-fail 'worker.finished.connect(thread.quit)' \
              'worker.finished.connect(thread.quit, Qt.ConnectionType.DirectConnection)'
            # GUI refresh must obey the same declarative-shortcut policy as CLI.
            substituteInPlace src/winpodx/gui/workers.py \
              --replace-fail 'def sync_desktop_entries(discovered) -> None:' \
              $'def sync_desktop_entries(discovered) -> None:\n    import os\n    if os.environ.get("WINPODX_DECLARATIVE_SHORTCUTS") == "1":\n        return'
            # GNOME renders DBusMenu remotely. Clearing an unchanged submenu
            # replaces its action IDs and makes the shell collapse it.
            substituteInPlace src/winpodx/desktop/tray.py \
              --replace-fail '    _enable_native_menu_scrolling(apps_menu)' \
              $'    if getattr(apps_menu, "_winpodx_snapshot", None) == available_apps:\n        return True\n    _enable_native_menu_scrolling(apps_menu)' \
              --replace-fail $'    apps_menu.addAction(desktop_action)\n    return True' \
              $'    apps_menu.addAction(desktop_action)\n    apps_menu._winpodx_snapshot = available_apps\n    return True' \
              --replace-fail 'apps_menu.aboutToShow.connect(_rebuild_apps_menu)' \
              'menu.aboutToShow.connect(_rebuild_apps_menu)' \
              --replace-fail $'    def _rebuild_sessions_menu() -> None:\n        sessions_menu.clear()' \
              '    def _rebuild_sessions_menu() -> None:' \
              --replace-fail '        # Parent each QAction to the submenu' \
              $'        snapshot = tuple(s.app_name for s in active)\n        if getattr(sessions_menu, "_winpodx_snapshot", None) == snapshot:\n            return\n        sessions_menu.clear()\n        sessions_menu._winpodx_snapshot = snapshot\n        # Parent each QAction to the submenu' \
              --replace-fail 'sessions_menu.aboutToShow.connect(_rebuild_sessions_menu)' \
              'menu.aboutToShow.connect(_rebuild_sessions_menu)' \
              --replace-fail $'    def _rebuild_devices_menu() -> None:\n        devices_menu.clear()' \
              '    def _rebuild_devices_menu() -> None:' \
              --replace-fail '        # Parent QActions to the submenu' \
              $'        snapshot = (usb, assigned)\n        if getattr(devices_menu, "_winpodx_snapshot", None) == snapshot:\n            return\n        devices_menu.clear()\n        devices_menu._winpodx_snapshot = snapshot\n        # Parent QActions to the submenu' \
              --replace-fail 'devices_menu.aboutToShow.connect(_rebuild_devices_menu)' \
              'menu.aboutToShow.connect(_rebuild_devices_menu)'
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
              '["systemd-run", "--user", "--scope", "--quiet", "--collect", *self._compose_cmd(), "up", "-d", *flags],'
            substituteInPlace src/winpodx/utils/deps.py \
              --replace-fail '    hint = f"{cmd} CLI found but its daemon is unreachable"' \
              $'    if cmd == "podman" and ("newuidmap" in low or "newgidmap" in low):\n        return (False, "Podman user-namespace setup failed; check that /run/wrappers/bin precedes raw newuidmap/newgidmap in PATH")\n    hint = f"{cmd} CLI found but its daemon is unreachable"'
            # Avoid pasta copying thousands of DN42 routes. DNS goes through
            # slirp's host-loopback mapping to the existing host resolver.
            substituteInPlace src/winpodx/core/pod/compose.py \
              --replace-fail '        template += _COMPOSE_PODMAN_EXTRAS' \
              $'        template += _COMPOSE_PODMAN_EXTRAS + "    network_mode: slirp4netns:allow_host_loopback=true,enable_ipv6=false\\n    dns: [10.0.2.2]\\n    dns_opt: [no-aaaa]\\n"'
            # Native pod start does not run setup_cmd's token preparation.
            # Stage it before the first OEM boot, using the upstream helper.
            substituteInPlace src/winpodx/core/pod/compose.py \
              --replace-fail $'    return str(user_oem)\n\n\ndef _render_storage_blocks' \
              $'    from winpodx.utils.agent_token import stage_token_to_oem\n    stage_token_to_oem(user_oem)\n    return str(user_oem)\n\n\ndef _render_storage_blocks'
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
          "${guard}/bin:/run/wrappers/bin:${
            lib.makeBinPath [
              pkgs.util-linux
              pkgs.coreutils
              pkgs.slirp4netns
            ]
          }"
          "--set-default"
          "WINPODX_DECLARATIVE_SHORTCUTS"
          "1"
        ];
      })
    );
  };
}
