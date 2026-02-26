{
  stdenvNoCC,
  source,
}:
stdenvNoCC.mkDerivation {
  inherit (source) src pname version;

  patchPhase = ''
    rm -rf .github tools lua .cnb.yml .gitignore .ide LICENSE README* demo.webp || true
    rm -f default.yaml squirrel.yaml weasel.yaml ibus_rime.yaml rime.lua symbols.yaml terra_symbols.yaml
    rm -f double_pinyin*.schema.yaml melt_eng.* radical_pinyin.* rime_ice.schema.yaml t9.schema.yaml
    rm -f opencc/emoji.* opencc/others.* opencc/spoken.* opencc/t9.*
    rm -f stroke.* terra_pinyin.* luna_pinyin.* bopomofo.* cangjie.* custom_phrase.txt
  '';

  installPhase = ''
    mkdir -p $out/share/rime-data
    cp -r * $out/share/rime-data/
  '';

  passthru.rimeDependencies = [ ];
}
