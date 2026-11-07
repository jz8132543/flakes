{
  stdenvNoCC,
  fetchzip,
  unzip,
}:
stdenvNoCC.mkDerivation {
  pname = "TheTVDB";
  version = "22.0.0.0";
  src = fetchzip {
    url = "https://repo.jellyfin.org/releases/plugin/thetvdb/thetvdb_22.0.0.0.zip";
    hash = "sha256-X7XDq1rdwg5WrueKMI2NmZYvBGe0yzqe3QfF69+qgyE=";
    stripRoot = false;
  };
  nativeBuildInputs = [ unzip ];
  dontUnpack = true;
  dontFixup = true;

  installPhase = ''
    if [ -d "$src" ]; then
      source_root="$src"
    else
      mkdir unpacked
      unzip "$src" -d unpacked
      source_root="unpacked"
    fi

    # Some plugin archives wrap files in a single top-level directory.
    shopt -s nullglob dotglob
    entries=("$source_root"/*)

    if [ "''${#entries[@]}" -eq 1 ] && [ -d "''${entries[0]}" ]; then
      cp -a "''${entries[0]}" "$out"
    else
      mkdir -p "$out"
      cp -a "$source_root"/. "$out/"
    fi
  '';

  passthru.pluginDirName = "TheTVDB_22.0.0.0";
}
