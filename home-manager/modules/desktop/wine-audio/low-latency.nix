{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.wineAudio;
  inherit (cfg) lowLatency;
  d274Root = "${cfg.dataDirectory}/D-274";
  project = "${d274Root}/projects/d274-carla.carxp";
  lowLatencyLauncher = pkgs.writeShellApplication {
    name = "vsl-concert-d274-low-latency";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      pipewire
      pulseaudio
      util-linux
    ];
    text = ''
      root=${lib.escapeShellArg d274Root}
      project=${lib.escapeShellArg project}
      rate=${lib.escapeShellArg (toString lowLatency.sampleRate)}
      quantum=${lib.escapeShellArg (toString lowLatency.quantum)}
      tools="$root/carla-tools/result"
      midi='Midi-Bridge:USB MIDI Interface: MIDI 1 (capture)'
      card=alsa_card.usb-Topping_E2x2-00
      sink=alsa_output.usb-Topping_E2x2-00.pro-output-0
      client=D274-Carla

      fail() { printf '%s\n' "$*" >&2; exit 1; }
      [[ -f "$project" && -d "$root/prefix" && -x "$tools/bin/yabridge-host.exe" && -x "$tools/bin/python" ]] ||
        fail "D-274 project, Wine prefix or pinned bridge is missing under $root."
      exec 9>"''${XDG_RUNTIME_DIR:?}/vsl-concert-d274.lock"
      flock -n 9 || fail "The D-274 launcher is already running."

      unset PIPEWIRE_RATE PIPEWIRE_QUANTUM PIPEWIRE_LATENCY
      if pactl list short cards | cut -f2 | grep -Fx "$card" >/dev/null; then
        if ! pw-link -i | grep -Fx "$sink:playback_AUX0" >/dev/null; then
          pactl set-card-profile "$card" pro-audio || fail "Cannot select Pro Audio on the E2x2."
        fi
        left="$sink:playback_AUX0"
        right="$sink:playback_AUX1"
        # Only this launcher and its children inherit the tested limits.
        if [[ $(ulimit -r) == 0 || ( $(ulimit -l) != unlimited && $(ulimit -l) -lt 65536 ) ]]; then
          /run/wrappers/bin/sudo ${pkgs.util-linux}/bin/prlimit --pid "$$" --rtprio=25 --memlock=67108864 ||
            fail "Cannot obtain realtime limits for Carla."
        fi
        export PIPEWIRE_RATE="1/$rate" PIPEWIRE_QUANTUM="$quantum/$rate" PIPEWIRE_LATENCY="$quantum/$rate"
      else
        sink=$(pactl get-default-sink) || sink=
        left="''${sink:+$sink:playback_FL}"
        right="''${sink:+$sink:playback_FR}"
        printf 'E2x2 not connected; using the desktop audio rate and buffer.\n'
      fi

      local_config=$(mktemp -d "$XDG_RUNTIME_DIR/d274-carla.XXXXXX")
      umask 077
      log="$XDG_RUNTIME_DIR/vsl-concert-d274.log"
      cleanup() {
        if [[ -n ''${host:-} ]]; then
          kill "$host" 2>/dev/null || true
          wait "$host" || true
        fi
        rm -r -- "$local_config"
      }
      trap cleanup EXIT
      trap 'exit 130' INT
      trap 'exit 143' TERM
      export WINEPREFIX="$root/prefix"
      export XDG_CONFIG_HOME="$local_config"
      export XDG_DATA_HOME="$root/xdg-data"
      export XDG_CACHE_HOME="$root/xdg-cache"
      export XDG_STATE_HOME="$root/xdg-state"
      export TMPDIR="$root/temp"
      export WINEDLLOVERRIDES=winemenubuilder.exe=d
      export WINEDEBUG=-all
      export QT_QPA_PLATFORM=xcb
      export NIX_PROFILES="''${NIX_PROFILES:-} $tools"
      export CARLA_DONT_MANAGE_CONNECTIONS=1
      export PIPEWIRE_PROPS='{ jack.self-connect-mode = fail-external jack.global-buffer-size = false }'
      export PATH="$tools/bin:$PATH"

      "$tools/bin/pw-jack" "$tools/bin/python" ${./scripts/d274-editor.py} "$tools" "$project" "$client" >"$log" 2>&1 9>&- &
      host=$!
      for ((attempt = 0; attempt < 120; attempt++)); do
        kill -0 "$host" 2>/dev/null || fail "Carla exited while loading D-274. See $log"
        if grep -Fxq 'D-274 project loaded' "$log"; then break; fi
        sleep 0.25
      done
      grep -Fxq 'D-274 project loaded' "$log" || fail "Timed out loading D-274. See $log"
      if [[ -n "$left" ]] && pw-link -i | grep -Fx "$left" >/dev/null && pw-link -i | grep -Fx "$right" >/dev/null; then
        pw-link -w "$client:VSL-D274:output_1" "$left"
        pw-link -w "$client:VSL-D274:output_2" "$right"
      else
        printf 'No stereo playback ports found. The VSL editor is available without audio.\n' >&2
      fi
      if pw-link -o | grep -Fx "$midi" >/dev/null; then
        pw-link -w "$midi" "$client:VSL-D274:events-in"
      fi
      printf 'D-274 loaded. Close the editor or press Ctrl-C to stop. Log: %s\n' "$log"
      wait "$host" || fail "The D-274 host stopped with an error. See $log"
    '';
  };
in
{
  options.programs.wineAudio.lowLatency = {
    enable = lib.mkEnableOption "the high-rate low-latency VSL Carla launcher";
    sampleRate = lib.mkOption {
      type = lib.types.ints.positive;
      default = 192000;
      description = "PipeWire graph sample rate used by the VSL launcher.";
    };
    quantum = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1536;
      description = "PipeWire graph quantum used by the VSL launcher.";
    };
  };

  config = lib.mkIf (cfg.enable && lowLatency.enable) {
    xdg.desktopEntries.vsl-concert-d274-low-latency = {
      name = "VSL Concert D-274 - Low Latency Carla";
      genericName = "Piano instrument";
      comment = "Open VSL Concert D-274 through Carla, yabridge and PipeWire JACK";
      icon = "audio-x-generic";
      terminal = true;
      startupNotify = false;
      categories = [
        "AudioVideo"
        "Audio"
        "Midi"
      ];
      settings = {
        Keywords = "VSL;Concert;D-274;Piano;Carla;yabridge;PipeWire;JACK;";
        Path = d274Root;
      };
      exec = lib.getExe lowLatencyLauncher;
    };
    xdg.dataFile."applications/vsl-concert-d274-low-latency.desktop".source = "${
      lib.findFirst (
        package: package.name == "vsl-concert-d274-low-latency.desktop"
      ) (throw "Missing Home Manager VSL low-latency desktop entry package") config.home.packages
    }/share/applications/vsl-concert-d274-low-latency.desktop";
  };
}
