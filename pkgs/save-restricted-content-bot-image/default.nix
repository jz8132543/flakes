{ pkgs, ... }:

let
  source = pkgs.save-restricted-content-bot;
  copyToRoot = pkgs.runCommand "save-restricted-content-bot-copy-root" { } ''
    mkdir -p $out/app
    mkdir -p $out/bin
    cp -r ${source}/. $out/app/
    ln -s ${pkgs.python3}/bin/python3 $out/bin/python3
    ln -s ${pkgs.ffmpeg}/bin/ffmpeg $out/bin/ffmpeg
  '';
in
pkgs.dockerTools.buildImage {
  name = "localhost/save-restricted-content-bot";
  tag = source.version or "latest";
  inherit copyToRoot;
  extraCommands = ''
    # install python dependencies via pip so we don't rely on nixpkgs pyrogram
    if [ -f /app/requirements.txt ]; then
      ${pkgs.python3.interpreter} -m pip install --no-cache-dir -r /app/requirements.txt
    fi
  '';
  config = {
    Cmd = [
      "python3"
      "/app/main.py"
    ];
    WorkingDir = "/app";
  };
}
