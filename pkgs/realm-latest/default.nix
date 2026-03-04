{
  stdenv,
  source,
  lib,
  rustPlatform,
  cmake,
  perl,
  llvmPackages,
  ...
}:
rustPlatform.buildRustPackage {
  pname = "realm";
  inherit (source) src version;

  cargoLock.lockFile = "${source.src}/Cargo.lock";

  doCheck = false;

  nativeBuildInputs = [
    cmake
    perl
    llvmPackages.libclang.lib
  ];

  LIBCLANG_PATH = "${llvmPackages.libclang.lib}/lib";
  BINDGEN_EXTRA_CLANG_ARGS = "-I${stdenv.cc.libc.dev}/include";

  env.RUSTC_BOOTSTRAP = 1;

  # Enable all performance features including jemalloc, batched-udp, zero-copy, multi-thread, proxy, tls, etc.
  buildNoDefaultFeatures = true;
  buildFeatures = [
    "jemalloc"
    "proxy"
    "balance"
    "multi-thread"
    "transport"
    "transport-tls-awslc"
    "batched-udp"
    "brutal-shutdown"
  ];

  # Extreme optimization flags
  env.RUSTFLAGS = "-C target-cpu=x86-64-v3 -C opt-level=3 -C lto=fat -C codegen-units=1 -C panic=abort";

  meta = with lib; {
    description = "A simple, high performance relay server written in Rust";
    homepage = "https://github.com/zhboner/realm";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "realm";
  };
}
