{
  lib,
  sources,
  appimageTools,
  nodejs_24,
}:
let
  pname = "openhands-desktop";
  inherit (sources.openhands-desktop) version src;
  contents = appimageTools.extract {
    inherit pname version src;
    postExtract = ''
      install -m644 ${./remote-main.mjs} $out/resources/app/remote-main.mjs
      substituteInPlace $out/resources/app/package.json \
        --replace-fail '"main": "main.mjs"' '"main": "remote-main.mjs"'
    '';
  };
in
appimageTools.wrapAppImage {
  inherit
    pname
    version
    src
    contents
    ;

  extraPkgs = pkgs: [
    pkgs.git
    pkgs.cacert
  ];

  extraInstallCommands = ''
    install -Dm444 ${contents}/agent-canvas.desktop $out/share/applications/agent-canvas.desktop
    substituteInPlace $out/share/applications/agent-canvas.desktop \
      --replace-fail "Exec=AppRun --no-sandbox" "Exec=${pname}"
    cp -r ${contents}/usr/share/icons $out/share/

    mkdir -p "$TMPDIR/openhands-tests"
    cp ${./remote-main.mjs} "$TMPDIR/openhands-tests/remote-main.mjs"
    cp ${./tests.mjs} "$TMPDIR/openhands-tests/tests.mjs"
    ${nodejs_24}/bin/node --experimental-vm-modules --test "$TMPDIR/openhands-tests/tests.mjs"
  '';

  meta = {
    description = "OpenHands desktop preview with optional authenticated remote mode";
    homepage = "https://github.com/OpenHands/OpenHands";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
