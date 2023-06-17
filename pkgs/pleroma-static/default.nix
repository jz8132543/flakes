{
  stdenv,
  emptyDirectory,
  akkoma-frontends,
  masto-fe,
  swagger-ui,
  fedibird-fe,
  pleroma-fe,
  soapbox,
}:
stdenv.mkDerivation {
  name = "akkoma-static";
  src = emptyDirectory;
  akkoma_fe = akkoma-frontends.akkoma-fe;
  akkoma_admin_fe = akkoma-frontends.admin-fe;
  masto_fe = masto-fe;
  swagger_ui = swagger-ui;
  fedibird_fe = fedibird-fe;
  pleroma_fe = pleroma-fe;
  soapbox = soapbox;
  dontUnpack = false;
  installPhase = ''
    mkdir -p $out/frontends/akkoma-fe/stable
    cp -r $akkoma_fe/* $out/frontends/akkoma-fe/stable
    mkdir -p $out/frontends/admin-fe/stable
    cp -r $akkoma_admin_fe/* $out/frontends/admin-fe/stable
    mkdir -p $out/frontends/mastodon-fe/stable
    cp -r $masto_fe/* $out/frontends/mastodon-fe/stable
    mkdir -p $out/frontends/swagger-ui/stable
    cp -r $swagger_ui/* $out/frontends/swagger-ui/stable
    mkdir -p $out/frontends/fedibird-fe/stable
    cp -r $fedibird_fe/* $out/frontends/fedibird-fe/stable
    mkdir -p $out/frontends/pleroma-fe/stable
    cp -r $pleroma_fe/* $out/frontends/pleroma-fe/stable
    mkdir -p $out/frontends/soapbox/stable
    cp -r $soapbox/* $out/frontends/soapbox/stable
    chmod -R +w $out
    # mkdir $out/static
    # cp $tos $out/static/terms-of-service.html
  '';
}
