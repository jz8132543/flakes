{
  stdenv,
  lib,
  fetchFromGitHub,
  kernel,
  source ? { },
  ...
}:

stdenv.mkDerivation rec {
  pname = "ms912x";
  version = source.version or "b502d3f";

  src =
    source.src or (fetchFromGitHub {
      owner = "rhgndf";
      repo = "ms912x";
      rev = "b502d3f2d7c513ccf37c3cceea51ca40abde4ca4";
      hash = "sha256-5SMMVXftgfpf/pfRCTvirMO9Ey4cMD3x/5ganxBYdaA=";
    });

  hardeningDisable = [
    "pic"
    "format"
  ];
  nativeBuildInputs = kernel.moduleBuildDependencies;

  buildPhase = ''
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M=$(pwd) modules
  '';

  installPhase = ''
    install -D ms912x.ko $out/lib/modules/${kernel.modDirVersion}/extra/ms912x.ko
  '';

  meta = with lib; {
    description = "MacroSilicon USB Display (MS912x) Linux DRM driver";
    homepage = "https://github.com/rhgndf/ms912x";
    license = licenses.gpl2Only;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}
