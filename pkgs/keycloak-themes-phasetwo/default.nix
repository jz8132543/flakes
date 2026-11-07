{
  lib,
  stdenvNoCC,
  sources,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "keycloak-themes-phasetwo";
  inherit (sources.keycloak-themes-phasetwo) version src;

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
