final: prev: {
  sources = prev.callPackage (import ./_sources/generated.nix) { };
  # mason-lspconfig = prev.callPackage ./mason-lspconfig { };
}
