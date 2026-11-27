{
  buildGoModule,
  fetchFromGitHub,
  lib,
  rustPlatform,
  stdenv,
  clang,
  llvmPackages,
  openssl,
  pkg-config,
}:
let
  version = "0.5.6";
  src = fetchFromGitHub {
    owner = "PinkD";
    repo = "corplink-rs";
    rev = "f00315959ef19fcb9aed191085f403d43d9355fd";
    hash = "sha256-bpETzZ0bA6eWK23zLAG3hGOPzJTOhVFrZnbyNf1A38k=";
  };
  wireguardGo = fetchFromGitHub {
    owner = "PinkD";
    repo = "wireguard-go";
    rev = "8936d2de0f2587fabeff9be7053eaef719d506d7";
    hash = "sha256-MPr38cHwsJP3CH1mkMQFB4EZemp2bSaiNrqFRCC4h/E=";
  };
  libwg = buildGoModule {
    pname = "corplink-libwg";
    inherit version;
    src = wireguardGo;
    patches = [ ./patches/wireguard-go/0001-cleanup-netstack-listener.patch ];
    vendorHash = "sha256-ihsFS2SuI1iqACHnJesgJD14k08XMsuwUGE8w+Mwl+k=";
    nativeBuildInputs = [ clang ];
    buildPhase = ''
      runHook preBuild
      printf 'package main\n\nconst Version = "%s"\n' "${version}" > version.go
      cp version.go libwg/version.go
      go build -trimpath -buildmode=c-archive -o libwg/libwg.a ./libwg
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm644 libwg/libwg.a "$out/lib/libwg.a"
      install -Dm644 libwg/libwg.h "$out/include/libwg.h"
      runHook postInstall
    '';
    checkPhase = ''
      runHook preCheck
      go test ./libwg
      runHook postCheck
    '';
    doCheck = true;
  };
in
rustPlatform.buildRustPackage {
  pname = "corplink-rs";
  inherit version src;
  cargoLock.lockFile = "${src}/Cargo.lock";
  patches = [ ./reconnect-verified.patch ];
  nativeBuildInputs = [
    clang
    llvmPackages.libclang
    pkg-config
  ];
  buildInputs = [
    openssl
    stdenv.cc.cc.lib
  ];
  LIBCLANG_PATH = "${llvmPackages.libclang.lib}/lib";

  preBuild = ''
    install -Dm644 ${libwg}/lib/libwg.a libwg/libwg.a
    install -Dm644 ${libwg}/include/libwg.h libwg/libwg.h
  '';

  meta = {
    description = "Unofficial Rust client for Feilian (CorpLink) VPN";
    homepage = "https://github.com/PinkD/corplink-rs";
    license = lib.licenses.gpl2Only;
    mainProgram = "corplink-rs";
    platforms = lib.platforms.linux;
  };
}
