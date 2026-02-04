{
  lib,
  buildNpmPackage,
  source,
  python3,
  makeWrapper,
  nodejs_20,
  chromium,
  cmake,
}:

buildNpmPackage {
  inherit (source) pname version src;
  nodejs = nodejs_20;

  npmFlags = [ "--omit=optional" ];

  # Set to fakeHash to get the actual hash during the first build
  npmDepsHash = "sha256-tb+elBNzcK7eYhGWTClHwh12AleWwNbQJhgpzvztBUU=";

  nativeBuildInputs = [
    python3
    makeWrapper
    cmake
  ];

  env.PUPPETEER_SKIP_CHROMIUM_DOWNLOAD = true;
  env.PUPPETEER_EXECUTABLE_PATH = "${chromium}/bin/chromium";
  env.CMAKE_POLICY_VERSION_MINIMUM = "3.5";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/node_modules/vertex
    cp -r . $out/lib/node_modules/vertex

    # Install dependencies
    # buildNpmPackage usually does this in buildPhase? 
    # But usually it installs to lib/node_modules/NAME.

    mkdir -p $out/bin
    makeWrapper ${nodejs_20}/bin/node $out/bin/vertex \
      --add-flags "$out/lib/node_modules/vertex/app/app.js" \
      --prefix PATH : ${lib.makeBinPath [ chromium ]} \
      --set PUPPETEER_EXECUTABLE_PATH ${chromium}/bin/chromium \
      --set PUPPETEER_SKIP_CHROMIUM_DOWNLOAD true

    # Handle UI if present in webui folder
    # Assuming webui needs to be in app/static?
    # Dockerfile: COPY src/static /app/vertex/app/static
    # If the repo HAS webui folder, we copy it to app/static?
    if [ -d $out/lib/node_modules/vertex/webui ]; then
      mkdir -p $out/lib/node_modules/vertex/app/static
      cp -r $out/lib/node_modules/vertex/webui/* $out/lib/node_modules/vertex/app/static/
    fi

    runHook postInstall
  '';

  meta = with lib; {
    description = "Vertex PT Tool";
    homepage = "https://github.com/vertex-app/vertex";
    license = licenses.mit; # Check LICENSE file
    maintainers = with maintainers; [ ];
  };
}
