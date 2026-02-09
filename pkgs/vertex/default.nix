{
  lib,
  buildNpmPackage,
  source,
  python3,
  makeWrapper,
  nodejs_20,
  chromium,
  cmake,
  git,
}:

let
  # Build the frontend (webui) separately with proper publicPath
  webui = buildNpmPackage {
    pname = "vertex-webui";
    inherit (source) version;

    src = "${source.src}/webui";

    nodejs = nodejs_20;

    # Apply the subpath patch before building
    prePatch = ''
      # Patch vue.config.js to use /vertex/ as publicPath
      sed -i "s|publicPath: '/'|publicPath: '/vertex/'|g" vue.config.js
      sed -i "s|start_url: '/'|start_url: '/vertex/'|g" vue.config.js

      # Remove the chainWebpack block that uses git commands
      # Replace with a simplified version that doesn't need git
      awk '
        /chainWebpack: config => \{/ { 
          in_block = 1
          print "  chainWebpack: config => {"
          print "    config.plugin(\"html\").tap(args => { args[0].title = \"Vertex\"; return args; });"
          print "    config.plugin(\"define\").tap((args) => {"
          print "      args[0][\"process.env\"].version = JSON.stringify({"
          print "        updateTime: \"${source.version}\","
          print "        head: \"${source.version}\","
          print "        commitInfo: \"nix-build\","
          print "        version: \"${source.version}\""
          print "      });"
          print "      return args;"
          print "    });"
          next
        }
        in_block && /^\s*\},\s*$/ { in_block = 0; print "  },"; next }
        in_block { next }
        { print }
      ' vue.config.js > vue.config.js.tmp && mv vue.config.js.tmp vue.config.js
    '';

    # This hash needs to be updated after first build attempt
    npmDepsHash = "sha256-g0L2/4mSe2DTEl/b9I7d7gE5rg/FuNTr35TMmDIEj60=";

    nativeBuildInputs = [ git ];

    # The build script is defined in package.json
    npmBuildScript = "build";

    installPhase = ''
      runHook preInstall
      # The build output goes to ../app/static based on vue.config.js outputDir
      mkdir -p $out
      cp -r ../app/static/* $out/
      runHook postInstall
    '';
  };
in

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

  # Don't try to build the webui here, we use the pre-built one
  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/node_modules/vertex
    cp -r . $out/lib/node_modules/vertex

    # Copy pre-built webui to app/static
    mkdir -p $out/lib/node_modules/vertex/app/static
    cp -r ${webui}/* $out/lib/node_modules/vertex/app/static/

    mkdir -p $out/bin
    makeWrapper ${nodejs_20}/bin/node $out/bin/vertex \
      --add-flags "$out/lib/node_modules/vertex/app/app.js" \
      --prefix PATH : ${lib.makeBinPath [ chromium ]} \
      --set PUPPETEER_EXECUTABLE_PATH ${chromium}/bin/chromium \
      --set PUPPETEER_SKIP_CHROMIUM_DOWNLOAD true

    runHook postInstall
  '';

  meta = with lib; {
    description = "Vertex PT Tool (with /vertex/ subpath support)";
    homepage = "https://github.com/vertex-app/vertex";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
  };
}
