{
  config,
  lib,
  pkgs,
  osConfig ? { },
  ...
}:
let
  hasNvidia = lib.elem "nvidia" (osConfig.services.xserver.videoDrivers or [ ]);
  hasPodman = osConfig.virtualisation.podman.enable or false;
  hasDocker = osConfig.virtualisation.docker.enable or false;
  views = [
    "cpu  Per-core user/system/iowait/steal"
    "interrupts  Hardware/software interrupts"
    "memory  Memory, swap, paging and context switches"
    "pressure  CPU/memory/I/O pressure and load"
    "disk  IOPS, latency, queue depth and utilization"
    "filesystems  Capacity, inode usage and block devices"
    "network  Per-interface throughput/errors and TCP"
    "connections  TCP/UDP sockets and owning processes"
    "sensors  Temperatures, fan speeds and voltages"
    "process  Select a PID and open detailed views"
    "smart  Read-only disk health (may require privileges)"
  ]
  ++ lib.optional hasNvidia "gpu  NVIDIA utilization, clocks, power, memory and I/O"
  ++ lib.optional hasPodman "podman  Current user Podman container statistics"
  ++ lib.optional hasDocker "docker  Docker container statistics";
  details = pkgs.writeShellApplication {
    name = "btm-detail";
    text = ''
      export LC_ALL=C
      mode="''${1:-menu}"
      if (( $# )); then shift; fi

      select_pid() {
        pid="''${1:-}"
        if [[ -z "$pid" ]]; then
          selection=$(${pkgs.procps}/bin/ps -eo pid,user,pcpu,pmem,args --sort=-pcpu |
            ${pkgs.fzf}/bin/fzf --header-lines=1 --prompt='Process > ' --no-multi) || return
          read -r pid _ <<< "$selection"
        fi
        if [[ ! "$pid" =~ ^[1-9][0-9]*$ || ! -d "/proc/$pid" ]]; then
          printf 'Process does not exist or PID is invalid: %s\n' "$pid" >&2
          return 1
        fi
      }

      case "$mode" in
        menu)
          trap ':' INT
          while selection=$(printf '%s\n' ${lib.escapeShellArgs views} |
              ${pkgs.fzf}/bin/fzf --prompt='Performance > ' --no-multi \
                --header='Select a view; Ctrl-C exits live views; Esc closes this menu'); do
            read -r action _ <<< "$selection"
            "$0" "$action" || {
              status=$?
              if (( status != 130 )); then
                printf 'View exited with status %s; permissions may limit the data.\n' "$status" >&2
                read -r -p 'Press Enter to return to the menu. ' _ || break
              fi
            }
          done
          ;;
        cpu) exec ${pkgs.sysstat}/bin/mpstat -P ALL 1 ;;
        interrupts) exec ${pkgs.sysstat}/bin/mpstat -I ALL 1 ;;
        memory) exec ${pkgs.procps}/bin/vmstat -w 1 ;;
        pressure) exec ${pkgs.procps}/bin/watch -n 1 -- "$0" pressure-snapshot ;;
        pressure-snapshot)
          ${pkgs.procps}/bin/uptime
          ${pkgs.procps}/bin/free -h
          for resource in cpu memory io; do
            printf '\n%s pressure (avg10/60/300 are percentages):\n' "$resource"
            if [[ -r "/proc/pressure/$resource" ]]; then
              ${pkgs.coreutils}/bin/cat "/proc/pressure/$resource"
            else
              printf 'Unavailable on this kernel or for this user.\n'
            fi
          done
          ;;
        disk) exec ${pkgs.sysstat}/bin/iostat -xz -y 1 ;;
        filesystems) exec ${pkgs.procps}/bin/watch -n 2 -- "$0" filesystem-snapshot ;;
        filesystem-snapshot)
          ${pkgs.coreutils}/bin/df -hT
          printf '\nInode usage:\n'
          ${pkgs.coreutils}/bin/df -hi
          printf '\nBlock devices:\n'
          ${pkgs.util-linux}/bin/lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS
          if [[ -r /proc/mdstat ]]; then
            printf '\nSoftware RAID:\n'
            ${pkgs.coreutils}/bin/cat /proc/mdstat
          fi
          ;;
        network) exec ${pkgs.sysstat}/bin/sar -n DEV,EDEV,TCP,ETCP,SOCK 1 ;;
        connections) exec ${pkgs.procps}/bin/watch -n 2 -- ${pkgs.iproute2}/bin/ss -tunap ;;
        sensors) exec ${pkgs.procps}/bin/watch -n 2 -- ${pkgs.lm_sensors}/bin/sensors ;;
        ${lib.optionalString hasNvidia ''
          gpu) exec ${osConfig.hardware.nvidia.package}/bin/nvidia-smi dmon -s pucmet -d 1 ;;
        ''}
        ${lib.optionalString hasPodman ''
          podman) exec ${pkgs.podman}/bin/podman stats ;;
        ''}
        ${lib.optionalString hasDocker ''
          docker) exec ${pkgs.docker}/bin/docker stats ;;
        ''}
        process)
          select_pid "''${1:-}"
          trap ':' INT
          while selection=$(printf '%s\n' \
            'process-live  CPU/memory/I/O/context switches, including threads' \
            'process-info  Command, status, affinity and counters' \
            'process-files  Open files and sockets' \
            'process-maps  Detailed memory mappings' \
            'process-threads  Thread CPU, state and scheduling' \
            | ${pkgs.fzf}/bin/fzf --prompt="PID $pid > " --no-multi); do
            read -r action _ <<< "$selection"
            "$0" "$action" "$pid" || true
          done
          ;;
        process-live|process-info|process-files|process-maps|process-threads)
          select_pid "''${1:-}"
          case "$mode" in
            process-live) exec ${pkgs.sysstat}/bin/pidstat -druwt -p "$pid" 1 ;;
            process-info)
              {
                ${pkgs.procps}/bin/ps -ww -p "$pid" \
                  -o pid,ppid,user,stat,ni,pri,psr,nlwp,pcpu,pmem,rss,vsz,etime,args
                printf '\nStatus (memory values in kB):\n'
                ${pkgs.coreutils}/bin/cat "/proc/$pid/status"
                printf '\nI/O counters (bytes, not rates):\n'
                ${pkgs.coreutils}/bin/cat "/proc/$pid/io" || true
              } | ${pkgs.less}/bin/less -SR
              ;;
            process-files) ${pkgs.lsof}/bin/lsof -nP -p "$pid" | ${pkgs.less}/bin/less -SR ;;
            process-maps) ${pkgs.procps}/bin/pmap -x "$pid" | ${pkgs.less}/bin/less -SR ;;
            process-threads)
              exec ${pkgs.procps}/bin/watch -n 1 -- ${pkgs.procps}/bin/ps -L -p "$pid" \
                -o pid,tid,psr,pcpu,stat,ni,pri,comm
              ;;
          esac
          ;;
        smart)
          device="''${1:-}"
          if [[ -z "$device" ]]; then
            selection=$(${pkgs.util-linux}/bin/lsblk -dnpo NAME,TYPE,MODEL |
              ${pkgs.fzf}/bin/fzf --prompt='SMART device > ' --no-multi) || exit 0
            read -r device _ <<< "$selection"
          fi
          if [[ "$device" != /dev/* || ! -b "$device" ]]; then
            printf 'Not a block device: %s\n' "$device" >&2
            exit 1
          fi
          ${pkgs.smartmontools}/bin/smartctl -a "$device" | ${pkgs.less}/bin/less -SR
          ;;
        -h|--help|help)
          printf '%s\n' \
            'Usage: btm-detail [VIEW] [PID|DEVICE]' \
            'No arguments: interactive diagnostics menu.' \
            'Views: cpu interrupts memory pressure disk filesystems network connections sensors' \
            '       process process-live process-info process-files process-maps process-threads smart' \
            'Snapshots use less: arrows scroll, q returns. Live views: Ctrl-C returns.' \
            'No automatic privilege escalation, persistent recording, or background services.'
          ${lib.optionalString hasNvidia ''printf '%s\n' 'GPU view: gpu';''}
          ${lib.optionalString hasPodman ''printf '%s\n' 'Container view: podman (current user; run explicitly as root for rootful containers)';''}
          ${lib.optionalString hasDocker ''printf '%s\n' 'Container view: docker';''}
          ;;
        *) printf 'Unknown view: %s\n' "$mode" >&2; exit 2 ;;
      esac
    '';
  };
in
{
  programs.bottom = {
    enable = true;
    settings = {
      flags = {
        # Sub-second refresh can make this version's Linux process I/O rates zero.
        rate = "1s";
        retention = "15m";
        default_time_value = "2m";
        time_delta = "30s";
        table_gap = "space";
        show_table_scroll_position = true;
        show_table_scroll_bar = true;
      };
      cpu = {
        default = "all";
        show_decimal = true;
        hide_avg_cpu = false;
      };
      memory_graph = {
        cache_memory = true;
        free_arc = true;
        short_gpu_names = false;
        legend_position = "top-left";
      };
      network_graph = {
        show_packets = true;
        use_bytes = true;
        use_binary_prefix = true;
        legend_position = "top-left";
        # Do not count packets again at container bridge/veth layers. Keep VPN/DN42 interfaces.
        interface_filter = {
          is_list_ignored = true;
          regex = true;
          whole_word = true;
          list = [
            "lo"
            "veth.*"
            "docker.*"
            "podman.*"
            "cni.*"
            "virbr.*"
          ];
        };
      };
      disk = {
        include_unmounted = true;
        columns = [
          "Disk"
          "Mount"
          "Used%"
          "Free"
          "Total"
          "R/s"
          "W/s"
          "Used"
          "Free%"
        ];
      };
      disk_io_graph = {
        include_unmounted = true;
        show_read = true;
        show_write = true;
        legend = "disk";
        legend_position = "top-left";
      };
      temperature.default_sort = "Temp";
      temperature.sort_order = "Descending";
      temperature_graph.legend_position = "top-left";
      processes = {
        default_sort = "CPU%";
        default_memory_value = true;
        process_command = true;
        hide_k_threads = true;
        # top-threads enables individual threads on demand without slowing the default view.
        get_threads = false;
        columns = [
          "PID"
          "Name"
          "CPU%"
          "Mem"
          "GPU%"
          "GMem"
          "R/s"
          "W/s"
          "User"
          "State"
          "Time"
          "Virt"
          "T.Read"
          "T.Write"
          "Nice"
          "Priority"
        ];
      };
      styles = {
        theme = "nord";
        cpu = {
          all_entry_colour = "#88c0d0";
          avg_entry_colour = "#ebcb8b";
        };
        memory = {
          ram_colour = "#b48ead";
          cache_colour = "#d08770";
          swap_colour = "#ebcb8b";
        };
        network = {
          rx_colour = "#a3be8c";
          tx_colour = "#bf616a";
        };
        tables.headers = {
          colour = "#88c0d0";
          bold = true;
        };
        widgets = {
          border_colour = "#4c566a";
          selected_border_colour = "#88c0d0";
          thread_text = {
            colour = "#a3be8c";
          };
        };
      };
      # Network is full-width so packet statistics can appear; e expands every component.
      row = [
        {
          ratio = 22;
          child = [
            {
              type = "cpu";
              ratio = 6;
            }
            {
              type = "mem";
              ratio = 4;
            }
            {
              type = "batt";
              ratio = 1;
            }
          ];
        }
        {
          ratio = 18;
          child = [ { type = "net"; } ];
        }
        {
          ratio = 22;
          child = [
            {
              type = "disk_io_graph";
              ratio = 3;
            }
            {
              type = "temp_graph";
              ratio = 2;
            }
            {
              ratio = 3;
              child = [
                { type = "disk"; }
                { type = "temp"; }
              ];
            }
          ];
        }
        {
          ratio = 38;
          child = [
            {
              type = "proc";
              default = true;
            }
          ];
        }
      ];
    };
  };

  programs.tmux.extraConfig = lib.mkIf config.programs.tmux.enable (
    lib.mkAfter ''
      # Explicit diagnostics menu while btm keeps running in its original pane.
      bind-key M display-popup -E -w 95% -h 90% "${details}/bin/btm-detail"
    ''
  );

  sops.secrets."ssh/id_ed25519".path = ".ssh/id_ed25519";
  home.file.".ssh/id_ed25519.pub" = {
    source = pkgs.writeText "pub" config.lib.self.data.ssh.i;
    force = true;
  };
  home.global-persistence = {
    directories = [
      ".cache/nix"
      ".gemini"
      ".android"
      ".config/kilo"
      ".local/share/kilo"
      ".local/state/kilo"
    ];
  };
  home.sessionVariables = { };
  # home.activation.syncOwnerPermissions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  #   sync_permissions() {
  #     local target_dir="$1"
  #     if [ -d "$target_dir" ]; then
  #       echo "Syncing permissions in $target_dir..."
  #       find "$target_dir" -mindepth 1 | while read -r item; do
  #         owner_perms=$(stat -c "%u" "$item")
  #         perms=$(stat -c "%a" "$item")
  #         owner_digit="''${perms:0:1}"
  #         new_perms="''${owner_digit}''${perms:1:1}''${owner_digit}"
  #         chmod "$new_perms" "$item" || true
  #       done
  #     fi
  #   }
  #   sync_permissions "/home/tippy/source"
  # '';

  home.packages = with pkgs; [
    duf
    sops
    home-manager
    details
  ];
}
