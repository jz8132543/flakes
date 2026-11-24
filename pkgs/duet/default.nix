{
  lib,
  pkgsCuda,
  makeWrapper,
  fetchFromGitHub,
}:
let
  inherit (pkgsCuda) python3Packages;
  inherit (python3Packages) torch;
  source = fetchFromGitHub {
    owner = "wei-zeng98";
    repo = "DuET";
    rev = "ba5a21466fba4c70c60e851cff65ae47c96de963";
    hash = "sha256-AId7QGsVG+9wGAp7zzyHORMzKI4vCWwOfvKHvUMHv4g=";
  };
  runtimePython = python3Packages.python.withPackages (_: [
    python3Packages.numpy
    python3Packages.mido
    python3Packages.safetensors
    python3Packages.huggingface-hub
    python3Packages.pandas
    python3Packages.scipy
    torch
  ]);
in

python3Packages.buildPythonApplication {
  pname = "duet-score";
  version = "0.1.0";
  pyproject = true;
  src = source;
  build-system = with python3Packages; [
    setuptools
    wheel
  ];
  dependencies =
    with python3Packages;
    [
      numpy
      mido
      safetensors
      huggingface-hub
      pandas
      scipy
    ]
    ++ [ torch ];
  pythonRelaxDeps = [
    "huggingface-hub"
    "torch"
  ];
  pythonImportsCheck = [ "duet" ];
  nativeBuildInputs = [ makeWrapper ];
  postInstall = ''
    cat > $out/bin/duet-prepare <<'PY'
    #!${runtimePython}/bin/python
    import sys
    sys.path.insert(0, "$out/${python3Packages.python.sitePackages}")
    from duet import DuET
    DuET.from_pretrained(sys.argv[1] if len(sys.argv) > 1 else "Wayne42/DuET")
    PY
    chmod 0755 $out/bin/duet-prepare
  '';
  meta = {
    description = "Piano MIDI performance-to-score transcription with DuET";
    homepage = "https://github.com/wei-zeng98/DuET";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "duet";
  };
}
