{
  pkgs,
  pkg,
  extraArgs ? "",
}:
pkgs.symlinkJoin {
  name = "${pkg.name}-no-ime";
  paths = [ pkg ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    for bin in $out/bin/*; do
      if [ -f "$bin" ] && [ -x "$bin" ]; then
        wrapProgram "$bin" \
          --set GTK_IM_MODULE "none" \
          --set QT_IM_MODULE "none" \
          --set SDL_IM_MODULE "none" \
          --set GLFW_IM_MODULE "none" \
          --set XMODIFIERS "@im=none" \
          --unset XIM ${extraArgs}
      fi
    done
  '';
}
