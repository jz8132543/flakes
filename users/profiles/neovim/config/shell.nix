with import <nixpkgs> {};
mkShell {
  buildInputs = with pkgs; [
    clang
    clang-tools
    clang-analyzer
  ];
  shellHook = ''
    export CLANG=${pkgs.clang}/bin/clang
    export CLANGD=${pkgs.clang-tools}/bin/clangd
  '';
}
