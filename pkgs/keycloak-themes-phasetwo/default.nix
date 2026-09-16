{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "keycloak-themes-phasetwo";
  version = "0.77";

  src = fetchurl {
    url = "https://repo1.maven.org/maven2/io/phasetwo/keycloak/keycloak-themes/${finalAttrs.version}/keycloak-themes-${finalAttrs.version}.jar";
    hash = "sha256-d3crWrz6qQbx7g+nDThhrN79wbEzu/CanIrKYYFWyKM=";
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm0444 $src $out/keycloak-themes-${finalAttrs.version}.jar
    runHook postInstall
  '';

  meta = with lib; {
    description = "Phase Two Keycloak themes and theme utilities, featuring phasetwo-ui (Keycloakify + shadcn/ui)";
    homepage = "https://github.com/p2-inc/keycloak-themes";
    license = licenses.elastic20;
    platforms = platforms.all;
  };
})
