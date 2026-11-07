{
  plex,
  plexRaw,
  fetchurl,
}:
plex.override {
  plexRaw = plexRaw.overrideAttrs (_old: rec {
    version = "1.41.4.9463-630c9f557";
    src = fetchurl {
      url = "https://downloads.plex.tv/plex-media-server-new/${version}/debian/plexmediaserver_${version}_amd64.deb";
      sha256 = "aa14f01ff0e6f09123981653c11e43fffa71305719e0e23a8e16ce4914ad9180";
    };
  });
}
