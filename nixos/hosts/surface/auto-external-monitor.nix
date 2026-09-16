{ pkgs, ... }:
let
  autoExternalMonitorPy = pkgs.writeText "auto-external-monitor.py" ''
    import json
    import subprocess
    import sys
    import time

    DEST = "org.gnome.Mutter.DisplayConfig"
    PATH = "/org/gnome/Mutter/DisplayConfig"
    IFACE = "org.gnome.Mutter.DisplayConfig"

    def run(cmd):
        return subprocess.check_output(cmd, text=True).strip()

    def variant_data(value):
        if isinstance(value, dict) and "data" in value:
            return value["data"]
        return value

    def get_state():
        payload = json.loads(
            run([
                "busctl", "--user", "--json=short", "call",
                DEST, PATH, IFACE, "GetCurrentState"
            ])
        )
        serial, monitors, logical_monitors, properties = payload["data"]
        return serial, monitors, logical_monitors, properties

    def quote_gvariant_string(value):
        return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"

    def props_to_gvariant(props):
        if not props:
            return "{}"
        rendered = []
        for key, value in props.items():
            if isinstance(value, bool):
                variant = "<true>" if value else "<false>"
            elif isinstance(value, int):
                variant = f"<uint32 {value}>"
            elif isinstance(value, float):
                variant = f"<{value}>"
            else:
                variant = f"<{quote_gvariant_string(str(value))}>"
            rendered.append(f"{quote_gvariant_string(key)}: {variant}")
        return "{" + ", ".join(rendered) + "}"

    def choose_mode(monitor):
        modes = monitor[1]
        for flag in ("is-current", "is-preferred"):
            for mode in modes:
                if variant_data(mode[6].get(flag, False)):
                    return mode
        return modes[0]

    def build_external_only_config():
        serial, monitors, logical_monitors, properties = get_state()
        monitor_map = {tuple(monitor[0]): monitor for monitor in monitors}
        builtin_map = {
            tuple(monitor[0]): bool(variant_data(monitor[2].get("is-builtin", False)))
            for monitor in monitors
        }
        external_specs = [spec for spec, builtin in builtin_map.items() if not builtin]
        layout_mode = variant_data(properties.get("layout-mode"))
        apply_properties = {}
        if layout_mode is not None:
            apply_properties["layout-mode"] = layout_mode

        if not external_specs:
            builtin_active = any(
                any(builtin_map.get(tuple(spec), False) for spec in lm[5])
                for lm in logical_monitors
            )
            if builtin_active:
                return None
            builtin_specs = [spec for spec, builtin in builtin_map.items() if builtin]
            if not builtin_specs:
                return None
            builtin_spec = builtin_specs[0]
            builtin_monitor = monitor_map[builtin_spec]
            mode = choose_mode(builtin_monitor)
            scale = float(mode[4]) if len(mode) > 4 and mode[4] else 1.0
            target_logical_monitors = [
                (0, 0, scale, 0, True, [(builtin_spec[0], mode[0], {})])
            ]
            return serial, logical_monitors, target_logical_monitors, apply_properties

        target_logical_monitors = []
        cursor_x = 0
        for index, spec in enumerate(external_specs):
            monitor = monitor_map[spec]
            mode = choose_mode(monitor)
            scale = float(mode[4]) if len(mode) > 4 and mode[4] else 1.0
            width = int(mode[1])
            target_logical_monitors.append(
                (
                    cursor_x,
                    0,
                    scale,
                    0,
                    index == 0,
                    [(spec[0], mode[0], {})],
                )
            )
            cursor_x += max(1, int(width / max(scale, 1.0)))

        return serial, logical_monitors, target_logical_monitors, apply_properties

    def logical_monitor_to_gvariant(logical_monitor):
        x, y, scale, transform, primary, monitors = logical_monitor
        rendered_monitors = ", ".join(
            f"({quote_gvariant_string(connector)}, {quote_gvariant_string(mode_id)}, {props_to_gvariant(props)})"
            for connector, mode_id, props in monitors
        )
        return (
            f"({x}, {y}, {scale}, uint32 {transform}, "
            f"{'true' if primary else 'false'}, [{rendered_monitors}])"
        )

    def apply_external_only():
        config = build_external_only_config()
        if config is None:
            return 0
        serial, current_logical_monitors, logical_monitors, properties = config
        current_connectors = [[spec[0] for spec in lm[5]] for lm in current_logical_monitors]
        target_connectors = [[monitor[0] for monitor in lm[5]] for lm in logical_monitors]

        if len(current_logical_monitors) == len(logical_monitors):
            unchanged = all(
                current[0] == target[0]
                and current[1] == target[1]
                and float(current[2]) == float(target[2])
                and int(current[3]) == int(target[3])
                and bool(current[4]) == bool(target[4])
                and connectors == target_connector_group
                for current, target, connectors, target_connector_group in zip(
                    current_logical_monitors,
                    logical_monitors,
                    current_connectors,
                    target_connectors,
                    strict=True,
                )
            )
            if unchanged:
                return 0

        rendered_logical_monitors = "[" + ", ".join(
            logical_monitor_to_gvariant(logical_monitor)
            for logical_monitor in logical_monitors
        ) + "]"

        subprocess.run(
            [
                "gdbus", "call", "--session",
                "--dest", DEST, "--object-path", PATH,
                "--method", f"{IFACE}.ApplyMonitorsConfig",
                str(serial), "2", rendered_logical_monitors,
                props_to_gvariant(properties),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        return 0

    def watch():
        while True:
            try:
                apply_external_only()
            except Exception:
                pass

            monitor = subprocess.Popen(
                ["gdbus", "monitor", "--session", "--dest", DEST, "--object-path", PATH],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )
            try:
                for line in monitor.stdout:
                    if "MonitorsChanged" not in line:
                        continue
                    time.sleep(1)
                    try:
                        apply_external_only()
                    except Exception:
                        pass
            finally:
                monitor.terminate()
                try:
                    monitor.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    monitor.kill()
            time.sleep(2)

    if __name__ == "__main__":
        watch()
  '';

  autoExternalMonitor = pkgs.writeShellApplication {
    name = "auto-external-monitor";
    runtimeInputs = [
      pkgs.python3
      pkgs.systemd
      pkgs.glib
    ];
    text = ''
      exec ${pkgs.python3.interpreter} ${autoExternalMonitorPy} "$@"
    '';
  };
in
{
  systemd.user.services."auto-external-monitor" = {
    description = "Automatically switch to external monitor only";
    partOf = [ "gnome-session-initialized.target" ];
    after = [ "gnome-session-initialized.target" ];
    wantedBy = [ "gnome-session.target" ];
    serviceConfig = {
      ExecStart = "${autoExternalMonitor}/bin/auto-external-monitor";
      Restart = "always";
      RestartSec = 3;
    };
  };
}
