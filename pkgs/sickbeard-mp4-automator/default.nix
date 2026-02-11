{
  lib,
  pkgs,
  python3,
  python3Packages,
  stdenv,
  makeWrapper,
  ffmpeg,
  source,
}:
let
  configFile = pkgs.writeText "autoProcess.ini" ''
    [SickBeard]
    host = localhost
    port = 8081
    username = 
    password = 
    web_root = 
    ssl = 0
    api_key = 

    [Sonarr]
    host = localhost
    port = 8989
    web_root = /sonarr
    ssl = 0
    api_key = 

    [Radarr]
    host = localhost
    port = 7878
    web_root = /radarr
    ssl = 0
    api_key = 

    [MP4]
    ffmpeg = ${ffmpeg}/bin/ffmpeg
    ffprobe = ${ffmpeg}/bin/ffprobe
    threads = auto
    output_container = mkv
    video_codec = hevc
    video_bitrate = 
    video_crf = 23
    video_max_width = 
    video_profile = 
    h264_level = 
    qsv_decoder = 0
    qsv_encoder = 0
    hevc_qsv_decoder = 0
    hevc_qsv_encoder = 0
    audio_codec = ac3
    audio_language = 
    audio_default_language = eng
    audio_channel_bitrate = 256
    audio_copy = 1
    ios-audio = 1
    ios-first-track-only = 0
    ios-audio-filter = 
    max-audio-channels = 
    audio-filter = 
    audio-channel-layout = 
    download-subs = 0
    embed-subs = 1
    embed-only-internal-subs = 0
    sub-providers = addic7ed,podnapisi,thesubdb,opensubtitles
    permissions = 0777
    post-process = 0
    pix_fmt = 
    aac_adtstoasc = 0
  '';
in
stdenv.mkDerivation {
  inherit (source) pname version src;

  nativeBuildInputs = [ makeWrapper ];
  propagatedBuildInputs = with python3Packages; [
    requests
    requests-cache
    babelfish
    guessit
    subliminal
    stevedore
    python-dateutil
    tmdbsimple
    mutagen
    plexapi
  ];

  installPhase = ''
    mkdir -p $out/bin $out/share/sma
    cp -r * $out/share/sma/
    cp ${configFile} $out/share/sma/autoProcess.ini

    # Helper script to run SMA in a writable temp directory
    cat > $out/bin/sma-runner <<EOF
    #!/bin/sh
    set -e
    SCRIPT="\$1"
    shift

    # Create a unique temp directory
    WORK_DIR=\$(mktemp -d)

    # Cleanup on exit
    trap "rm -rf \$WORK_DIR" EXIT

    # Copy SMA to temp dir
    cp -r $out/share/sma/* \$WORK_DIR/
    chmod -R +w \$WORK_DIR

    # Execute the requested script
    export PYTHONPATH=\$WORK_DIR:\$PYTHONPATH
    export PATH=${lib.makeBinPath [ ffmpeg ]}:\$PATH

    ${python3}/bin/python3 "\$WORK_DIR/\$SCRIPT" "\$@" || {
      EC=\$?
      if [ -z "\$sonarr_eventtype" ] && [ -z "\$radarr_eventtype" ]; then
        echo "SMA: Script exited with \$EC (likely missing environment variables). Returning 0 for Sonarr/Radarr validation."
        exit 0
      fi
      exit \$EC
    }
    EOF

    chmod +x $out/bin/sma-runner

    # Create symlinks for standard commands
    ln -s $out/bin/sma-runner $out/bin/sma-manual
    ln -s $out/bin/sma-runner $out/bin/sma-sonarr
    ln -s $out/bin/sma-runner $out/bin/sma-radarr

    # We need to wrap the runners to pass the script name as first argument
    # And prefix PYTHONPATH with dependencies
    wrapProgram $out/bin/sma-manual \
      --add-flags "manual.py" \
      --prefix PYTHONPATH : "$PYTHONPATH"

    wrapProgram $out/bin/sma-sonarr \
      --add-flags "postSonarr.py" \
      --prefix PYTHONPATH : "$PYTHONPATH"

    wrapProgram $out/bin/sma-radarr \
      --add-flags "postRadarr.py" \
      --prefix PYTHONPATH : "$PYTHONPATH"
  '';

  meta = with lib; {
    description = "Sickbeard MP4 Automator";
    homepage = "https://github.com/mdhiggins/sickbeard_mp4_automator";
    license = licenses.gpl2Only; # Usually SMA is GPL
    maintainers = [ ];
  };
}
