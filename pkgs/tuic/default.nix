{
  source,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  inherit (source) pname version src;
}
