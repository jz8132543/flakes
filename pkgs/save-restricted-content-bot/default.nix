# 只将源代码暴露到 Nix store，供 podman build 使用
{
  lib,
  pkgs,
  source,
  ...
}:
pkgs.stdenv.mkDerivation {
  inherit (source) pname version src;
  dontBuild = true;
  installPhase = ''
    cp -r . $out
  '';
  meta = with lib; {
    description = "Save Restricted Content Bot v3 — source for container build";
    homepage = "https://github.com/devgaganin/Save-Restricted-Content-Bot-v3";
    license = licenses.gpl3Only;
    maintainers = [ ];
  };
}
