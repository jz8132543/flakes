{ pkgs, sources, ... }:

let
  inherit (sources.save-restricted-content-bot) src;
  ver = sources.save-restricted-content-bot.version or "latest";
in
pkgs.dockerTools.buildImage {
  name = "localhost/save-restricted-content-bot";
  tag = ver;
  # include a plain python runtime and ffmpeg binary from nixpkgs
  contents = [
    pkgs.python3
    pkgs.ffmpeg
  ];
  copy = [
    {
      source = src;
      target = "/app";
    }
  ];
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
