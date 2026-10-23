{
  lib,
  stdenv,
  fetchFromGitHub,
  maven,
  openjdk17_headless,
  makeWrapper,
}:

let
  version = "8.0.2";
  src = fetchFromGitHub {
    owner = "apache";
    repo = "trafficcontrol";
    rev = "v${version}";
    sha256 = "1xcfd9g6zd9yli73pxsy98qdnilxpiwp5ar6hakyavjykg6kcpl6";
  };
in
stdenv.mkDerivation {
  pname = "traffic-router";
  inherit version src;

  nativeBuildInputs = [
    maven
    makeWrapper
  ];
  buildInputs = [ openjdk17_headless ];

  buildPhase = ''
    cd traffic_router
    echo "=== Now in: $(pwd) ==="
    echo "=== Checking for build/pom.xml ==="
    if [ -f ./build/pom.xml ]; then
      echo "Found ./build/pom.xml, patching rpm-maven-plugin extension..."
      sed -i 's/<extensions>true<\/extensions>/<!-- extensions removed for Nix build -->/' ./build/pom.xml || true
      echo "Patched"
    else
      echo "No ./build/pom.xml found"
    fi
    echo "=== Removing build module from parent POM ==="
    cd ..
    sed -i '/<module>build<\/module>/d' pom.xml || true
    echo "=== Running Maven ==="
    cd traffic_router
    mvn package -DskipTests -Dmaven.javadoc.skip=true
  '';

  installPhase = ''
    mkdir -p $out/bin $out/share/traffic-router

    # Locate the built Traffic Router JAR
    JAR_PATH="$(find traffic_router -type f -name 'traffic-router-*.jar' -path '*/target/*' | head -n 1 || true)"
    if [ -z "$JAR_PATH" ]; then
      echo "ERROR: traffic-router JAR not found after Maven build" >&2
      exit 1
    fi

    cp "$JAR_PATH" $out/share/traffic-router/traffic-router.jar

    makeWrapper ${openjdk17_headless}/bin/java $out/bin/traffic_router \
      --add-flags "-Xms128m -Xmx512m -jar $out/share/traffic-router/traffic-router.jar"
  '';

  meta = with lib; {
    description = "Apache Traffic Control Traffic Router (DNS & HTTP steering)";
    homepage = "https://trafficcontrol.apache.org/";
    license = licenses.asl20;
    platforms = platforms.linux;
  };
}
