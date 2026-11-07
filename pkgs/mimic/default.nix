{
  lib,
  stdenv,
  sources,
  bpftools,
  llvmPackages,
  libbpf,
  libffi,
  pkg-config,
}:

stdenv.mkDerivation {
  pname = "mimic";
  version = lib.removePrefix "v" sources.mimic.version;
  inherit (sources.mimic) src;

  patches = [
    ./0001-fix-esp-checksum.patch
  ];

  nativeBuildInputs = [
    bpftools
    llvmPackages.clang-unwrapped
    llvmPackages.bintools
    pkg-config
  ];

  buildInputs = [
    libbpf
    libffi
  ];

  hardeningDisable = [ "all" ];

  makeFlags = [
    "BPF_CC=clang"
    "BPFTOOL=bpftool"
    "LLVM_STRIP=llvm-strip"
    "CHECKSUM_HACK=kprobe"
  ];

  preBuild = ''
    export BPF_CFLAGS="--target=bpf -mcpu=v3 -g -O2 -I${libbpf}/include"
  '';

  buildFlags = [ "build-cli" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 out/mimic $out/bin/mimic
    runHook postInstall
  '';

  meta = with lib; {
    description = "eBPF-based UDP to fake-TCP obfuscator";
    homepage = "https://github.com/hack3ric/mimic";
    license = licenses.gpl2Only;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "mimic";
  };
}
