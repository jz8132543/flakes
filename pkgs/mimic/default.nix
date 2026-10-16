{
  lib,
  stdenv,
  fetchFromGitHub,
  bpftools,
  llvmPackages,
  libbpf,
  libffi,
  pkg-config,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "mimic";
  version = "0.7.1";

  src = fetchFromGitHub {
    owner = "hack3ric";
    repo = "mimic";
    rev = "v${finalAttrs.version}";
    hash = "sha256-7ztGGWX7asTgLFvSIunpeeb0lA2jWywD0U8v3uien1o=";
  };

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
})
