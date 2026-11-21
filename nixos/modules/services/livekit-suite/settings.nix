{
  # Pure defaults. Zero denotes no application-imposed video bitrate cap, not a WebRTC value.
  media = {
    adaptiveStream = true;
    dynacast = true;
    video = {
      codecPriority = [
        "av1"
        "h265"
        "vp9"
        "h264"
      ];
      width = 1920;
      height = 1080;
      frameRate = 60;
      maxBitrate = 0;
      scalabilityMode = "L3T3_KEY";
      simulcast = true;
      backupCodec = "h264";
      contentHint = "detail";
    };
    screenAudio = {
      audioBitrate = 256000;
      echoCancellation = false;
      noiseSuppression = false;
      autoGainControl = false;
      dtx = false;
      red = false;
    };
    voice = {
      audioBitrate = 64000;
      echoCancellation = true;
      noiseSuppression = true;
      autoGainControl = true;
      dtx = true;
      red = true;
    };
  };
  transport = {
    iceTransportPolicy = "all";
    iceCandidatePoolSize = 10;
    peerConnectionTimeout = 20000;
    websocketTimeout = 15000;
    maxRetries = 3;
  };
  control = {
    topic = "control.touch.v1";
    sampleRate = 120;
    maxContacts = 10;
    watchdogMs = 250;
  };
  server = {
    signalingPort = 17980;
    tcpPort = 17981;
    udpPortStart = 63000;
    udpPortEnd = 63999;
    packetBufferVideo = 2048;
    packetBufferAudio = 512;
    pliThrottle = {
      low_quality = "500ms";
      mid_quality = "1s";
      high_quality = "1s";
    };
    congestionControl = {
      enabled = true;
      allow_pause = true;
      use_send_side_bwe = true;
    };
    allowTcpFallback = true;
    nodeSelector = {
      kind = "regionaware";
      sort_by = "sysload";
      sysload_limit = 0.9;
    };
  };
  room = {
    auto_create = true;
    empty_timeout = 300;
    departure_timeout = 20;
    max_participants = 16;
    enable_remote_unmute = false;
  };
  turn = {
    port = 3480;
    tlsPort = 5350;
    proxyPort = 5351;
    tlsProxyPort = 5352;
    advertisedTlsPort = 443;
    relayStart = 64000;
    relayEnd = 64499;
    proxyRelayStart = 64500;
    proxyRelayEnd = 64999;
    relayThreads = 2;
    credentialTtl = 14400;
    userQuota = 12;
    totalQuota = 1024;
    staleNonce = 600;
  };
  redis = {
    port = 6390;
    maxMemory = "256mb";
  };
  web = {
    port = 17990;
    tokenTtl = 900;
    maxBodyBytes = 4096;
    requestsPerMinute = 30;
  };
}
