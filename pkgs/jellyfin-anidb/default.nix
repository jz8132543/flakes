{
  stdenvNoCC,
  fetchzip,
  unzip,
}:
stdenvNoCC.mkDerivation {
  pname = "AniDB";
  version = "13.0.0.0";
  src = fetchzip {
    url = "https://repo.jellyfin.org/files/plugin/anidb/anidb_13.0.0.0.zip";
    hash = "sha256-TiMl1kloW43CpKrLGaU9uZxrHi/oZHTA8Eu7MsRDneM=";
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

  passthru.pluginDirName = "AniDB_13.0.0.0";
}
