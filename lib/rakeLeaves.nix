{ lib, ... }:
dirPath:
let
  seive = file: type:
    # Only rake `.nix` files or directories
    (type == "regular" && lib.hasSuffix ".nix" file) || (type == "directory");

  collect = file: type: {
    name = lib.removeSuffix ".nix" file;
    value =
      let
        path = dirPath + "/${file}";
      in
      if (type == "regular")
        || (type == "directory" && builtins.pathExists (path + "/default.nix"))
      then path
      # recurse on directories that don't contain a `default.nix`
      else lib.rakeLeaves path;
  };

  files = lib.filterAttrs seive (builtins.readDir dirPath);
in
lib.filterAttrs (n: v: v != { }) (lib.mapAttrs' collect files)

