{
  inputs,
  self,
  ...
}:
[
  inputs.sops-nix.overlays.default
  inputs.rust-overlay.overlays.default
  inputs.antigravity-nix.overlays.default
  inputs.chinese-fonts-overlay.overlays.default
  (
    _final: prev:
    {
      # tailscale = prev.tailscale.overrideAttrs (old: {
      #   subPackages = [
      #     "cmd/tailscaled"
      #     "cmd/derper"
      #     "cmd/stunc"
      #     "cmd/hello"
      #   ];
      #   postInstall = lib.strings.concatStrings [
      #     "cp $out/bin/derper $out/bin/derp && "
      #     (old.postInstall or "")
      #   ];
      # });
    }
    // (self.lib.maybeAttrByPath "comma-with-db" inputs [
      "nix-index-database"
      "packages"
      prev.stdenv.hostPlatform.system
      "comma-with-db"
    ])
  )
  (final: prev: {
    qt6Packages = prev.qt6Packages.overrideScope (
      _qt6Final: qt6Prev: {
        libsForQt5 = (qt6Prev.libsForQt5 or (prev.libsForQt5.overrideScope (_: _: { }))).overrideScope (
          _qt5Final: _qt5Prev: {
            fcitx5-qt = null;
          }
        );
      }
    );

    inherit (final.qt6Packages) fcitx5-qt;

    fcitx5-configtool = prev.fcitx5-configtool.override { kcmSupport = false; };

    fcitx5-chinese-addons = prev.fcitx5-chinese-addons.override {
      enableCloudPinyin = false;
      enableOpencc = false;
      qtwebengine = null;
    };

    python3Packages = prev.python3Packages.overrideScope (
      pyFinal: pyPrev: {
        kde-material-you-colors = pyPrev.kde-material-you-colors.overridePythonAttrs (old: {
          propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [ pyFinal.python-magic ];
        });
      }
    );
  })
  (_final: prev: {
    nur = prev.nur // {
      repos = prev.nur.repos // {
        fym998 = prev.nur.repos.fym998 // {
          wpsoffice-cn-fcitx = prev.nur.repos.fym998.wpsoffice-cn-fcitx.overrideAttrs (old: {
            postInstall = (old.postInstall or "") + ''
              templatesDir=

              for candidate in ${../conf/wps/templates} ${../conf/wps}; do
                if [ -d "$candidate" ]; then
                  templatesDir="$candidate"
                  break
                fi
              done

              if [ -n "$templatesDir" ] && [ -d "$templatesDir" ]; then
                if [ -f "$templatesDir/newfile.docx" ]; then
                  install -Dm644 "$templatesDir/newfile.docx" "$out/opt/kingsoft/wps-office/templates/newfile.docx"
                  install -Dm644 "$templatesDir/newfile.docx" "$out/opt/kingsoft/wps-office/office6/mui/zh_CN/templates/newfile.docx"
                fi

                if [ -f "$templatesDir/newfile.xlsx" ]; then
                  install -Dm644 "$templatesDir/newfile.xlsx" "$out/opt/kingsoft/wps-office/templates/newfile.xlsx"
                  install -Dm644 "$templatesDir/newfile.xlsx" "$out/opt/kingsoft/wps-office/office6/mui/zh_CN/templates/newfile.xlsx"
                fi

                if [ -f "$templatesDir/newfile.pptx" ]; then
                  install -Dm644 "$templatesDir/newfile.pptx" "$out/opt/kingsoft/wps-office/templates/newfile.pptx"
                  install -Dm644 "$templatesDir/newfile.pptx" "$out/opt/kingsoft/wps-office/office6/mui/zh_CN/templates/newfile.pptx"
                fi
              fi

              if [ -f "$out/share/templates/wps-office-wps-template.desktop" ]; then
                sed -i 's|URL=.*|URL=/opt/kingsoft/wps-office/office6/mui/zh_CN/templates/newfile.docx|' \
                  "$out/share/templates/wps-office-wps-template.desktop"
              fi
              if [ -f "$out/share/templates/wps-office-et-template.desktop" ]; then
                sed -i 's|URL=.*|URL=/opt/kingsoft/wps-office/office6/mui/zh_CN/templates/newfile.xlsx|' \
                  "$out/share/templates/wps-office-et-template.desktop"
              fi
              if [ -f "$out/share/templates/wps-office-wpp-template.desktop" ]; then
                sed -i 's|URL=.*|URL=/opt/kingsoft/wps-office/office6/mui/zh_CN/templates/newfile.pptx|' \
                  "$out/share/templates/wps-office-wpp-template.desktop"
              fi

              for exe in $out/bin/*; do
                [ -x "$exe" ] || continue
                wrapProgram "$exe" \
                  --set-default LANG zh_CN.UTF-8 \
                  --set-default LANGUAGE zh_CN:zh \
                  --set-default LC_MESSAGES zh_CN.UTF-8
              done
            '';
          });
        };
      };
    };
  })
  (import "${self}/pkgs").overlay
]
