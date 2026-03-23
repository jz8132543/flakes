{
  lib,
  stdenv,
  rustPlatform,
  protobuf,
  installShellFiles,
  source,
  withQuic ? true,
}:

rustPlatform.buildRustPackage {
  pname = "easytier";
  inherit (source) src version;

  cargoRoot = "easytier";
  buildAndTestSubdir = "easytier";

  cargoLock = {
    lockFile = "${source.src}/Cargo.lock";
    allowBuiltinFetchGit = true;
  };

  postPatch = ''
    ln -sf ../Cargo.lock easytier/Cargo.lock
  '';

  nativeBuildInputs = [
    protobuf
    rustPlatform.bindgenHook
    installShellFiles
  ];

  buildNoDefaultFeatures = stdenv.hostPlatform.isMips;
  buildFeatures = lib.optional stdenv.hostPlatform.isMips "mips" ++ lib.optional withQuic "quic";
  cargoBuildFlags = [ "--package=easytier" ];

  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd easytier-cli \
      --bash <($out/bin/easytier-cli gen-autocomplete bash) \
      --fish <($out/bin/easytier-cli gen-autocomplete fish) \
      --zsh <($out/bin/easytier-cli gen-autocomplete zsh)
    installShellCompletion --cmd easytier-core \
      --bash <($out/bin/easytier-core --gen-autocomplete bash) \
      --fish <($out/bin/easytier-core --gen-autocomplete fish) \
      --zsh <($out/bin/easytier-core --gen-autocomplete zsh)
  '';

  doCheck = false;

  meta = with lib; {
    homepage = "https://github.com/EasyTier/EasyTier";
    description = "Simple, decentralized mesh VPN with WireGuard support";
    longDescription = ''
      EasyTier is a simple, safe and decentralized VPN networking solution implemented
      with the Rust language and Tokio framework.
    '';
    mainProgram = "easytier-core";
    license = licenses.asl20;
    platforms = with platforms; unix ++ windows;
  };
}
