{
  inputs,
  self,
  ...
}:
[
  inputs.sops-nix.overlays.default
  inputs.rust-overlay.overlays.default
  inputs.chinese-fonts-overlay.overlays.default
  (
    _final: prev:
    {
    }
    // (self.lib.maybeAttrByPath "comma-with-db" inputs [
      "nix-index-database"
      "packages"
      prev.stdenv.hostPlatform.system
      "comma-with-db"
    ])
  )
  (
    final: prev:
    let
      masterPkgs = inputs.latest.legacyPackages.${final.stdenv.hostPlatform.system};
      configureWps = final.writeShellScript "configure-wps" ''
        set -eu
        export PATH=${final.lib.makeBinPath [ final.coreutils ]}
        config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/Kingsoft"
        mkdir -p "$config_dir"
        exec 9>"$config_dir/.office-config.lock"
        ${final.util-linux}/bin/flock 9
        config_file="$config_dir/Office.conf"
        [ -e "$config_file" ] || touch "$config_file"
        tmp_file="$(mktemp "$config_dir/.Office.conf.XXXXXX")"
        trap 'rm -f "$tmp_file"' EXIT
        # Merge only managed keys; keep Qt's serialized values and user settings intact.
        ${final.gawk}/bin/awk '
          function flush(    key) {
            if (!(section in values)) return
            for (key in values[section])
              if (!written[section, key]++) print key "=" values[section][key]
          }
          BEGIN {
            values["General"]["languages"] = "zh_CN"
            values["6.0"]["common\\do_not_detect_file_association_while_startup"] = "true"
          }
          /^\[.*\]\r?$/ {
            flush()
            section = substr($0, 2, index($0, "]") - 2)
            seen[section] = 1
          }
          {
            key = substr($0, 1, index($0, "=") - 1)
            if (section in values && key in values[section]) {
              if (!written[section, key]++) print key "=" values[section][key]
            } else print
          }
          END {
            flush()
            for (section in values) {
              if (!seen[section]) {
                print "[" section "]"
                flush()
              }
            }
          }
        ' "$config_file" > "$tmp_file"
        if ! ${final.diffutils}/bin/cmp -s "$tmp_file" "$config_file"; then
          chmod --reference="$config_file" "$tmp_file"
          mv "$tmp_file" "$config_file"
        fi
      '';
      refreshWpsVersion = final.writeShellScript "refresh-wps-version" ''
        set -eu

        config_file="''${XDG_CONFIG_HOME:-$HOME/.config}/Kingsoft/Office.conf"
        lock_file="$HOME/.cache/wps-update-version.lock"
        mkdir -p "$(dirname "$lock_file")"
        exec 9>"$lock_file"
        ${final.util-linux}/bin/flock -n 9 || exit 0

        latest_version="$(${final.curl}/bin/curl \
          --fail --silent --show-error --location \
          --connect-timeout 1 --max-time 2 \
          'https://www.wps.cn/product/wpslinux' \
          | ${final.gnugrep}/bin/grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
          | ${final.coreutils}/bin/head -n 1 || true)"
        case "$latest_version" in
          [0-9]*.[0-9]*.[0-9]*.[0-9]*) ;;
          *) exit 0 ;;
        esac

        [ -f "$config_file" ] || exit 0
        # Serialize with the startup merge after the network request, not before it.
        exec 8>"$(dirname "$config_file")/.office-config.lock"
        ${final.util-linux}/bin/flock 8
        tmp_file="$(${final.coreutils}/bin/mktemp "$(dirname "$config_file")/.Office.conf.XXXXXX")"
        trap '${final.coreutils}/bin/rm -f "$tmp_file"' EXIT
        ${final.gawk}/bin/awk -v version="$latest_version" '
          BEGIN { in_section = 0; section_found = 0; found = 0 }
          /^\[UnixUpdateInfo\]$/ {
            in_section = 1
            section_found = 1
            print
            next
          }
          /^\[/ {
            if (in_section && !found) print "UserRejectUpdateVersion=" version
            in_section = 0
          }
          in_section && /^UserRejectUpdateVersion=/ {
            print "UserRejectUpdateVersion=" version
            found = 1
            next
          }
          { print }
          END {
            if (in_section && !found) print "UserRejectUpdateVersion=" version
            if (!section_found) {
              print "[UnixUpdateInfo]"
              print "UserRejectUpdateVersion=" version
            }
          }
        ' "$config_file" > "$tmp_file"
        ${final.coreutils}/bin/mv "$tmp_file" "$config_file"
        trap - EXIT
      '';
    in
    {
      wpsoffice-cn = prev.symlinkJoin {
        name = "${prev.wpsoffice-cn.name or "wpsoffice-cn"}-no-scale";
        inherit (prev.wpsoffice-cn) version meta;
        paths = [ prev.wpsoffice-cn ];
        passthru = (prev.wpsoffice-cn.passthru or { }) // {
          inherit configureWps;
        };
        nativeBuildInputs = [ prev.makeWrapper ];
        postBuild = ''
          for bin in $out/bin/*; do
            if [ -f "$bin" ] && [ -x "$bin" ]; then
              wrapProgram "$bin" \
                --run '${configureWps}' \
                --run '${refreshWpsVersion} >/dev/null 2>&1 &' \
                --set QT_AUTO_SCREEN_SCALE_FACTOR 0 \
                --set QT_ENABLE_HIGHDPI_SCALING 0 \
                --set QT_SCALE_FACTOR 1
            fi
          done
        '';
      };

      ms365 =
        if (inputs ? office365) && (prev.stdenv.hostPlatform.system == "x86_64-linux") then
          let
            orig = inputs.office365.packages.${prev.stdenv.hostPlatform.system}.default;
          in
          prev.symlinkJoin {
            name = "${orig.name or "ms365"}-gnome-auto-dpi";
            inherit (orig) meta;
            paths = [ orig ];
            nativeBuildInputs = [ prev.makeWrapper ];
            postBuild = ''
              for bin in $out/bin/ms365*; do
                if [ -f "$bin" ] && [ -x "$bin" ]; then
                  wrapProgram "$bin" \
                    --run '
                      if [ -z "$MS365_DPI" ]; then
                        scale=$(gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig --method org.gnome.Mutter.DisplayConfig.GetCurrentState 2>/dev/null | sed -E -n "s/.*\[\([0-9]+, [0-9]+, ([0-9.]+), uint32 [0-9]+, (true|false).*/\1/p")
                        if [ -z "$scale" ]; then
                          scale=$(gsettings get org.gnome.desktop.interface scaling-factor 2>/dev/null | awk "{print \$2}")
                          [ "$scale" = "0" ] || [ -z "$scale" ] && scale=1.0
                        fi
                        export MS365_DPI=$(awk -v s="$scale" "BEGIN { dpi = int(96 * s + 0.5); if (dpi >= 192) dpi = 180; print dpi }")
                      fi
                    '
                fi
              done
            '';
          }
        else
          null;

      # perlPackages = prev.perlPackages.overrideScope (
      #   _pfinal: _pprev: {
      #     URIws = prev.emptyDirectory;
      #   }
      # );
      #
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (_pyFinal: pyPrev: {
          pysaml2 = pyPrev.pysaml2.overridePythonAttrs (_: {
            doCheck = false;
          });
        })
      ];

      # TODO: 默认 nixpkgs 包含 #584958 后将包来源切回默认 nixpkgs。
      # TODO: 上游隔离 document_link/grammar 单测的共享缓存后移除此串行测试覆盖。
      neocmakelsp = masterPkgs.neocmakelsp.overrideAttrs (_: {
        dontUseCargoParallelTests = true;
      });

      # TODO: 默认 nixpkgs 包含 #584630 后移除此 master 临时覆盖。
      inherit (masterPkgs) intelli-shell;

      # TODO: 上游 nixpkgs 补齐 gersemi 的 pkg-config/sqlite 依赖后移除此临时覆盖。
      gersemi = prev.gersemi.overridePythonAttrs (old: {
        nativeBuildInputs = final.lib.unique ((old.nativeBuildInputs or [ ]) ++ [ final.pkg-config ]);
        buildInputs = final.lib.unique ((old.buildInputs or [ ]) ++ [ final.sqlite ]);
      });

      # TODO: 默认 nixpkgs 包含 #584667 后移除此 master 临时覆盖。
      inherit (masterPkgs) codex;

      # TODO: 上游 nixpkgs 补齐 cc-switch 的 sqlite 依赖后移除此临时覆盖。
      cc-switch = prev.cc-switch.overrideAttrs (old: {
        buildInputs = final.lib.unique ((old.buildInputs or [ ]) ++ [ final.sqlite ]);
      });

      matrix-synapse-unwrapped = prev.matrix-synapse-unwrapped.overrideAttrs (_old: {
        doCheck = false;
        dontCheck = true;
        checkPhase = "";
        doInstallCheck = false;
        dontInstallCheck = true;
        installCheckPhase = "";
        nativeCheckInputs = [ ];
      });

      matrix-synapse = prev.matrix-synapse.override {
        inherit (final) matrix-synapse-unwrapped;
      };
      qdrant = inputs.nixos-2605.legacyPackages.${final.stdenv.hostPlatform.system}.qdrant;
      rime-wanxiang-gram = inputs.rime-wanxiang-gram.outPath;
    }
    // prev.lib.optionalAttrs (prev ? anime-games-launcher) {
      # TODO: 上游 AAGL 为 anime-games-launcher 补齐 aws-lc/sqlite 依赖后移除此临时修复。
      anime-games-launcher = prev.anime-games-launcher.override {
        unwrapped = prev.anime-games-launcher.unwrapped.overrideAttrs (old: {
          buildInputs = final.lib.unique (
            (old.buildInputs or [ ])
            ++ [
              final.aws-lc
              final.sqlite
            ]
          );
        });
      };
    }
  )
  (import "${self}/pkgs").overlay
]
