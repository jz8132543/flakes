{
  callPackage,
  fetchFromGitHub,
  makeWrapper,
  onnxruntime,
  flavor ? "universal",
}:
assert !(onnxruntime.cudaSupport or false);
let
  source = fetchFromGitHub {
    owner = "LeonardNJU";
    repo = "VocoType-linux";
    rev = "878724b7c895f7faf01b3cae9fa646396491ee28"; # v5.0.9
    hash = "sha256-u3aMailuIk9OL8s/YWHNJgRquh/qlrg/hWBJlAA/HTc=";
  };
  upstream = callPackage (source + "/packaging/nix/package.nix") {
    inherit source flavor;
    inherit onnxruntime;
  };
  models = callPackage ./models.nix { };
in
upstream.overrideAttrs (old: {
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ makeWrapper ];
  postFixup = (old.postFixup or "") + ''
    wrapProgram "$out/bin/vocotype-settings" \
      --set MODELSCOPE_CACHE ${models}
    wrapProgram "$out/bin/vocotype-model-manager" \
      --set MODELSCOPE_CACHE ${models}
  '';
  passthru = (old.passthru or { }) // {
    inherit models;
  };
  meta = old.meta // {
    isIbusEngine = flavor != "fcitx5";
  };
})
