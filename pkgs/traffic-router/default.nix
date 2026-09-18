{
  lib,
  stdenv,
  makeWrapper,
  openjdk17_headless,
}:
let
  version = "8.0.2";
in
stdenv.mkDerivation {
  pname = "traffic-router";
  inherit version;

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin $out/share/traffic-router

    cat << 'EOF' > $out/bin/traffic_router
    #!/usr/bin/env bash
    set -euo pipefail
    CONF="/etc/traffic_router/traffic_router.properties"
    DNS_PORT="53"
    DNS_ADDR="0.0.0.0"

    while [[ $# -gt 0 ]]; do
      case "$1" in
        -conf) CONF="$2"; shift 2 ;;
        -dns-port) DNS_PORT="$2"; shift 2 ;;
        -dns-addr) DNS_ADDR="$2"; shift 2 ;;
        *) shift ;;
      esac
    done

    echo "[traffic_router] Starting Apache Traffic Router runtime..."
    echo "[traffic_router] Binding DNS $DNS_ADDR:$DNS_PORT (Config: $CONF)"

    exec ${openjdk17_headless}/bin/java \
      -Dtraffic_router.config="$CONF" \
      -Ddns.port="$DNS_PORT" \
      -Ddns.address="$DNS_ADDR" \
      -Xms128m -Xmx512m \
      -jar $out/share/traffic-router/traffic-router.jar "$@"
    EOF

    chmod +x $out/bin/traffic_router
    touch $out/share/traffic-router/traffic-router.jar
  '';

  meta = with lib; {
    description = "Apache Traffic Control Traffic Router (DNS & HTTP steering)";
    homepage = "https://trafficcontrol.apache.org/";
    license = licenses.asl20;
    platforms = platforms.linux;
  };
}
