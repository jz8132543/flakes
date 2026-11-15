(() => {
  "use strict";

  const $ = (id) => document.getElementById(id);
  const sdk = window.LivekitClient;
  const encoder = new TextEncoder();
  const localTracks = new Set();
  const audioNodes = new Map();
  const contacts = new Map();
  const releaseTimers = new Map();
  let cfg;
  let room = null;
  let phase = "idle";
  let generation = 0;
  let authAbort = null;
  let screenTracks = [];
  let micTrack = null;
  let screenBusy = false;
  let micBusy = false;
  let viewedTrack = null;
  let viewedPublication = null;
  let viewedIdentity = "";
  let supportedCodecs = [];
  let controlEnabled = false;
  let session = "";
  let seq = 0;
  let moveTimer = null;
  let heartbeatTimer = null;
  let dirty = false;
  let statsTimer = null;
  let statsBusy = false;
  let statsPrevious = new Map();
  let lastSnapshotAt = 0;

  function message(id, text) {
    $(id).textContent = text;
    $(id).hidden = !text;
  }

  function showError(text) {
    message("errorMessage", text);
  }

  function connected(r = room) {
    return (
      !!r &&
      r === room &&
      phase === "connected" &&
      r.state === sdk.ConnectionState.Connected
    );
  }

  function setStatus(text, state = phase) {
    $("connectionStatus").textContent = text;
    $("connectionStatus").dataset.state = state;
    $("transportStatus").textContent = text;
  }

  function validTarget() {
    const target = $("remoteParticipant").value;
    return (
      connected() &&
      !!session &&
      !!target &&
      room.remoteParticipants.has(target) &&
      viewedIdentity === target &&
      viewedTrack?.source === sdk.Track.Source.ScreenShare &&
      !viewedTrack.isMuted &&
      !viewedPublication?.isMuted &&
      viewedTrack.streamState !== sdk.Track.StreamState.Paused &&
      viewedTrack.mediaStreamTrack.readyState === "live" &&
      !viewedTrack.mediaStreamTrack.muted &&
      $("screenVideo").readyState >= 2 &&
      !$("screenVideo").paused &&
      $("screenVideo").videoWidth > 0 &&
      $("screenVideo").videoHeight > 0 &&
      !document.hidden
    );
  }

  function updateButtons() {
    const online = connected();
    const idle = phase === "idle";
    $("joinButton").disabled = !cfg || !idle;
    $("leaveButton").disabled = idle || phase === "leaving";
    $("roomName").disabled = !idle;
    $("nodeSelect").disabled = !cfg || !idle;
    $("joinKey").disabled = !idle;
    $("remoteParticipant").disabled = !online;
    $("shareButton").disabled =
      !online ||
      screenBusy ||
      !supportedCodecs.length ||
      !navigator.mediaDevices?.getDisplayMedia;
    $("shareButton").textContent = screenBusy
      ? "正在处理屏幕…"
      : screenTracks.length
        ? "停止共享屏幕"
        : "共享屏幕";
    $("micButton").disabled =
      !online || micBusy || !navigator.mediaDevices?.getUserMedia;
    $("micButton").textContent = micBusy
      ? "正在处理语音…"
      : !micTrack
        ? "开启语音麦克风"
        : micTrack.isMuted
          ? "取消语音静音"
          : "静音语音麦克风";
    $("micButton").setAttribute(
      "aria-pressed",
      String(!!micTrack && !micTrack.isMuted),
    );
    $("shareButton").setAttribute(
      "aria-pressed",
      String(screenTracks.length > 0),
    );
    $("startPlaybackButton").disabled = !online;
    $("controlConsent").disabled = !validTarget();
    $("controlButton").disabled =
      !controlEnabled && !(validTarget() && $("controlConsent").checked);
    $("controlButton").textContent = controlEnabled
      ? "停止触控发送"
      : "启用触控发送";
    $("controlButton").setAttribute("aria-pressed", String(controlEnabled));
    $("touchSurface").classList.toggle("enabled", controlEnabled);
    $("controlBadge").hidden = !controlEnabled;
    $("contactCount").textContent =
      `${contacts.size} / ${cfg?.control.maxContacts ?? 10}`;
  }

  function captureAudio(settings, stereo = false) {
    return {
      echoCancellation: settings.echoCancellation,
      noiseSuppression: settings.noiseSuppression,
      autoGainControl: settings.autoGainControl,
      channelCount: stereo ? 2 : 1,
    };
  }

  function publishAudio(settings, source) {
    return {
      source,
      audioPreset: { maxBitrate: settings.audioBitrate },
      dtx: settings.dtx,
      red: settings.red,
      forceStereo: source === sdk.Track.Source.ScreenShareAudio,
      stopMicTrackOnMute: source === sdk.Track.Source.Microphone,
    };
  }

  function codecCapabilities() {
    try {
      const sender =
        window.RTCRtpSender?.getCapabilities?.("video")?.codecs ?? [];
      const receiver =
        window.RTCRtpReceiver?.getCapabilities?.("video")?.codecs ?? [];
      const has = (list, codec) =>
        list.some((c) => c.mimeType.toLowerCase() === `video/${codec}`);
      return sdk.videoCodecs.filter((codec) => {
        if (!has(sender, codec) || !has(receiver, codec)) return false;
        if (codec === "av1") return sdk.supportsAV1();
        if (codec === "vp9") return sdk.supportsVP9();
        if (codec === "h265") return sdk.supportsH265();
        return true;
      });
    } catch {
      return [];
    }
  }

  function chooseCodec() {
    const explicit = $("codecSelect").value;
    if (explicit !== "auto") {
      if (!supportedCodecs.includes(explicit))
        throw new Error("所选编码不具备本机发送与接收能力。");
      return explicit;
    }
    const codec = [...cfg.media.video.codecPriority, "h264"].find(
      (c) => sdk.videoCodecs.includes(c) && supportedCodecs.includes(c),
    );
    if (!codec)
      throw new Error(
        "未检测到同时支持发送和接收的 LiveKit 视频编码，无法发布屏幕。",
      );
    return codec;
  }

  function publishVideo() {
    const codec = chooseCodec();
    const options = {
      videoCodec: codec,
      simulcast: cfg.media.video.simulcast,
      backupCodec: false,
      degradationPreference:
        $("contentHint").value === "motion"
          ? "maintain-framerate"
          : "maintain-resolution",
    };
    if (codec === "av1" || codec === "vp9") {
      options.scalabilityMode = cfg.media.video.scalabilityMode;
    }
    const backup = cfg.media.video.backupCodec;
    if (
      backup !== codec &&
      backup === "h264" &&
      supportedCodecs.includes(backup)
    ) {
      options.backupCodec = { codec: backup };
      options.backupCodecPolicy = sdk.BackupCodecPolicy.PREFER_REGRESSION;
    }
    // Omitting both encoding fields uses SDK defaults; zero is not an unlimited bitrate.
    if ($("limitBitrate").checked) {
      const encoding = {
        maxBitrate: Number($("maxBitrate").value) * 1000000,
        maxFramerate: Number($("frameRate").value),
      };
      options.videoEncoding = encoding;
      options.screenShareEncoding = { ...encoding };
      if (options.backupCodec) options.backupCodec.encoding = { ...encoding };
    }
    return options;
  }

  function refreshParticipants() {
    const select = $("remoteParticipant");
    const previous = select.value;
    const placeholder = new Option("选择远端参与者；未选择时显示本机预览", "");
    select.replaceChildren(placeholder);
    if (room) {
      for (const participant of room.remoteParticipants.values()) {
        const sharing = [...participant.videoTrackPublications.values()].some(
          (p) => p.source === sdk.Track.Source.ScreenShare,
        );
        select.add(
          new Option(
            `${participant.identity}${sharing ? " / 屏幕" : " / 无屏幕"}`,
            participant.identity,
          ),
        );
      }
    }
    if ([...select.options].some((o) => o.value === previous))
      select.value = previous;
    if (select.value !== previous)
      stopControl("目标已离开，请重新选择并授权。");
    refreshView();
  }

  function resetStats() {
    statsPrevious.clear();
    $("actualCodec").textContent = "等待统计";
    $("actualResolution").textContent = "等待统计";
    $("actualBitrate").textContent = "等待统计";
  }

  function refreshView() {
    const target = $("remoteParticipant").value;
    const participant = target ? room?.remoteParticipants.get(target) : null;
    const publication = participant
      ? [...participant.videoTrackPublications.values()].find(
          (p) => p.source === sdk.Track.Source.ScreenShare && p.track,
        )
      : null;
    const track = target
      ? (publication?.track ?? null)
      : (screenTracks.find((t) => t.source === sdk.Track.Source.ScreenShare) ??
        null);
    if (track !== viewedTrack || target !== viewedIdentity) {
      stopControl("屏幕或目标已切换，触控授权已清除。");
      viewedTrack?.detach($("screenVideo"));
      $("screenVideo").srcObject = null;
      viewedTrack = track;
      viewedPublication = publication;
      viewedIdentity = target;
      resetStats();
      if (track) {
        track.attach($("screenVideo"));
        $("screenVideo").muted = true;
        $("screenVideo")
          .play()
          .catch(() =>
            message(
              "noticeMessage",
              "浏览器阻止了画面自动播放，请点击“启用声音 / 播放”。",
            ),
          );
      }
    }
    const available = !!track && !track.isMuted && !publication?.isMuted;
    $("screenPlaceholder").hidden = available;
    $("viewIdentity").textContent = track
      ? target
        ? `远端屏幕 / ${target}`
        : "本机屏幕预览（静音，不发送触控）"
      : target
        ? `${target} 尚未提供可观看的屏幕`
        : "尚无屏幕";
    if (controlEnabled && !validTarget())
      stopControl("当前屏幕不可控制，已释放全部触点。");
    updateButtons();
  }

  function detachAudio(track) {
    const node = audioNodes.get(track);
    if (!node) return;
    track.detach(node);
    node.pause();
    node.srcObject = null;
    node.remove();
    audioNodes.delete(track);
  }

  function attachTrack(track) {
    if (track.kind === sdk.Track.Kind.Audio && !audioNodes.has(track)) {
      const node = document.createElement("audio");
      node.autoplay = true;
      node.setAttribute("playsinline", "");
      $("audioContainer").append(node);
      audioNodes.set(track, node);
      track.attach(node);
    }
    refreshParticipants();
  }

  function bindRoom(r) {
    const on = (event, handler) =>
      r.on(event, (...args) => {
        if (room === r) handler(...args);
      });
    on(sdk.RoomEvent.TrackSubscribed, attachTrack);
    on(sdk.RoomEvent.TrackUnsubscribed, (track) => {
      detachAudio(track);
      refreshParticipants();
    });
    for (const event of [
      sdk.RoomEvent.ParticipantConnected,
      sdk.RoomEvent.ParticipantDisconnected,
      sdk.RoomEvent.TrackPublished,
      sdk.RoomEvent.TrackUnpublished,
    ]) {
      on(event, refreshParticipants);
    }
    for (const event of [sdk.RoomEvent.TrackMuted, sdk.RoomEvent.TrackUnmuted])
      on(event, refreshView);
    on(sdk.RoomEvent.TrackStreamStateChanged, (publication, state) => {
      if (
        publication === viewedPublication &&
        state === sdk.Track.StreamState.Paused
      )
        stopControl("SFU 暂停了当前屏幕，触控已停止。");
      refreshView();
    });
    on(sdk.RoomEvent.LocalTrackUnpublished, (publication) => {
      if (screenTracks.includes(publication.track))
        void stopScreen(r).catch(() =>
          showError("停止屏幕发布失败，采集已关闭。"),
        );
      if (micTrack && publication.track === micTrack) {
        micTrack.stop();
        localTracks.delete(micTrack);
        micTrack = null;
        updateButtons();
      }
    });
    on(sdk.RoomEvent.TrackSubscriptionFailed, () =>
      showError("轨道订阅失败，请检查权限、浏览器编码支持及服务器连接。"),
    );
    on(sdk.RoomEvent.MediaDevicesError, () =>
      showError("采集设备不可用或权限被拒绝，请检查浏览器权限。"),
    );
    on(sdk.RoomEvent.AudioPlaybackStatusChanged, () => {
      if (!r.canPlaybackAudio)
        message(
          "noticeMessage",
          "声音尚未获准自动播放，请点击“启用声音 / 播放”。",
        );
    });
    on(sdk.RoomEvent.DCBufferStatusChanged, (isLow) => {
      if (!isLow && controlEnabled)
        stopControl("DataChannel 缓冲拥塞，触控已停止；原生看门狗须释放触点。");
    });
    on(sdk.RoomEvent.Reconnecting, () => {
      stopControl("连接中断，触控已停止；恢复后需要重新授权。");
      setStatus("连接中断，正在重连", "reconnecting");
      updateButtons();
    });
    on(sdk.RoomEvent.SignalReconnecting, () => {
      stopControl("信令重连，触控已停止。");
      setStatus("信令重连中", "reconnecting");
    });
    on(sdk.RoomEvent.Reconnected, () => {
      setStatus("已连接");
      refreshParticipants();
    });
    on(sdk.RoomEvent.Disconnected, () => {
      if (phase === "leaving") return;
      generation += 1;
      stopControl("房间已断开，触控和采集已停止。");
      room = null;
      cleanup();
      r.removeAllListeners();
      phase = "idle";
      setStatus("连接已断开");
      showError("房间连接已断开。重新加入需要再次输入密钥。");
      updateButtons();
    });
  }

  function clearReleaseTimers(target) {
    for (const [timer, context] of releaseTimers) {
      if (target === undefined || context.target === target) {
        clearTimeout(timer);
        releaseTimers.delete(timer);
      }
    }
  }

  function sendSnapshot(r, target, controlSession, points) {
    if (
      !r ||
      room !== r ||
      r.state !== sdk.ConnectionState.Connected ||
      !target ||
      !controlSession ||
      !r.remoteParticipants.has(target)
    )
      return;
    const payload = {
      v: 1,
      session: controlSession,
      seq: ++seq,
      type: "snapshot",
      points,
    };
    // Every release retry gets a newer sequence; native code must discard older packets.
    Promise.resolve()
      .then(() =>
        r.localParticipant.publishData(
          encoder.encode(JSON.stringify(payload)),
          {
            reliable: false,
            topic: cfg.control.topic,
            destinationIdentities: [target],
          },
        ),
      )
      .catch(() => {
        if (room === r && controlEnabled) {
          showError(
            "触控 DataChannel 发送失败，触控已停止。原生端应通过看门狗释放触点。",
          );
          stopControl("数据发送失败，请重新检查原生授权。");
        }
      });
  }

  function releaseContacts(retry = true) {
    clearTimeout(moveTimer);
    clearInterval(heartbeatTimer);
    moveTimer = heartbeatTimer = null;
    dirty = false;
    const pointers = [...contacts.keys()];
    contacts.clear();
    for (const pointer of pointers) {
      if ($("touchSurface").hasPointerCapture(pointer))
        $("touchSurface").releasePointerCapture(pointer);
    }
    const r = room;
    const target = viewedIdentity;
    const controlSession = session;
    if (retry && target && controlSession) {
      clearReleaseTimers(target);
      sendSnapshot(r, target, controlSession, []);
      for (const delay of [40, 80, 120]) {
        const timer = setTimeout(() => {
          releaseTimers.delete(timer);
          sendSnapshot(r, target, controlSession, []);
        }, delay);
        releaseTimers.set(timer, { target });
      }
    }
    updateButtons();
  }

  function stopControl(reason) {
    const wasActive = controlEnabled || contacts.size > 0;
    controlEnabled = false;
    $("controlConsent").checked = false;
    releaseContacts(wasActive);
    $("controlStatus").textContent = reason || "触控已关闭。";
    updateButtons();
  }

  function contentPoint(event) {
    const video = $("screenVideo");
    const rect = video.getBoundingClientRect();
    if (!video.videoWidth || !video.videoHeight || !rect.width || !rect.height)
      return null;
    const scale = Math.min(
      rect.width / video.videoWidth,
      rect.height / video.videoHeight,
    );
    const width = video.videoWidth * scale;
    const height = video.videoHeight * scale;
    const left = rect.left + (rect.width - width) / 2;
    const top = rect.top + (rect.height - height) / 2;
    const x = (event.clientX - left) / width;
    const y = (event.clientY - top) / height;
    if (
      !Number.isFinite(x) ||
      !Number.isFinite(y) ||
      x < 0 ||
      y < 0 ||
      x > 1 ||
      y > 1
    )
      return null;
    return { x, y };
  }

  function flushContacts() {
    if (!controlEnabled) return;
    if (!validTarget()) {
      stopControl("屏幕、连接或页面状态无效，已释放触点。");
      return;
    }
    for (const pointer of contacts.keys()) {
      if (!$("touchSurface").hasPointerCapture(pointer)) {
        stopControl("指针捕获丢失，已释放全部触点。");
        return;
      }
    }
    dirty = false;
    lastSnapshotAt = performance.now();
    const points = [...contacts.values()]
      .map(({ id, x, y }) => ({ id, x, y }))
      .sort((a, b) => a.id - b.id);
    sendSnapshot(room, viewedIdentity, session, points);
    updateButtons();
  }

  function scheduleMove() {
    dirty = true;
    if (moveTimer !== null) return;
    const delay = Math.ceil(
      Math.max(
        0,
        1000 / cfg.control.sampleRate - (performance.now() - lastSnapshotAt),
      ),
    );
    moveTimer = setTimeout(() => {
      moveTimer = null;
      if (dirty) flushContacts();
    }, delay);
  }

  function endContact(event) {
    if (!contacts.has(event.pointerId)) return;
    event.preventDefault();
    contacts.delete(event.pointerId);
    if ($("touchSurface").hasPointerCapture(event.pointerId))
      $("touchSurface").releasePointerCapture(event.pointerId);
    if (contacts.size) flushContacts();
    else releaseContacts();
  }

  $("touchSurface").addEventListener("pointerdown", (event) => {
    if (
      !controlEnabled ||
      !validTarget() ||
      event.button !== 0 ||
      contacts.has(event.pointerId)
    )
      return;
    const point = contentPoint(event);
    if (!point || contacts.size >= cfg.control.maxContacts) return;
    event.preventDefault();
    clearReleaseTimers(viewedIdentity);
    const ids = new Set([...contacts.values()].map((p) => p.id));
    let id = 0;
    while (ids.has(id)) id += 1;
    try {
      $("touchSurface").setPointerCapture(event.pointerId);
      contacts.set(event.pointerId, { id, ...point });
      flushContacts();
      if (controlEnabled && contacts.size > 0 && heartbeatTimer === null) {
        heartbeatTimer = setInterval(
          flushContacts,
          Math.min(75, cfg.control.watchdogMs / 3),
        );
      }
    } catch {
      stopControl("浏览器无法捕获指针，触控已停止。");
    }
  });
  $("touchSurface").addEventListener("pointermove", (event) => {
    if (!contacts.has(event.pointerId)) return;
    event.preventDefault();
    if (
      !controlEnabled ||
      !validTarget() ||
      (event.pointerType === "mouse" && !(event.buttons & 1))
    ) {
      stopControl("指针或屏幕状态失效，已释放触点。");
      return;
    }
    const point = contentPoint(event);
    if (!point) {
      endContact(event);
      return;
    }
    Object.assign(contacts.get(event.pointerId), point);
    scheduleMove();
  });
  $("touchSurface").addEventListener("pointerup", endContact);
  $("touchSurface").addEventListener("lostpointercapture", (event) => {
    if (contacts.has(event.pointerId))
      stopControl("指针捕获意外丢失，触控已停止。");
  });
  $("touchSurface").addEventListener("pointercancel", () =>
    stopControl("系统取消了触摸，触控已停止。"),
  );
  $("touchSurface").addEventListener("contextmenu", (event) => {
    if (controlEnabled) event.preventDefault();
  });

  async function stopScreen(r = room) {
    const tracks = screenTracks;
    screenTracks = [];
    for (const track of tracks) {
      localTracks.delete(track);
      track.stop();
    }
    refreshView();
    if (r && r.state === sdk.ConnectionState.Connected) {
      const results = await Promise.allSettled(
        tracks.map((track) => r.localParticipant.unpublishTrack(track)),
      );
      if (results.some((result) => result.status === "rejected"))
        throw new Error("屏幕采集已关闭，但取消发布失败。");
    }
  }

  async function shareScreen() {
    const r = room;
    const stamp = generation;
    if (!connected(r) || screenBusy) return;
    screenBusy = true;
    updateButtons();
    message("errorMessage", "");
    let acquired = [];
    try {
      if (screenTracks.length) {
        await stopScreen(r);
        return;
      }
      const options = publishVideo();
      const height = Number($("resolution").value);
      const width = { 1080: 1920, 1440: 2560, 2160: 3840 }[height];
      // Invoke capture before any await so getDisplayMedia retains the click gesture.
      acquired = await r.localParticipant.createScreenTracks({
        video: true,
        audio: $("includeScreenAudio").checked
          ? captureAudio(cfg.media.screenAudio, true)
          : false,
        resolution: { width, height, frameRate: Number($("frameRate").value) },
        contentHint: $("contentHint").value,
        systemAudio: $("includeScreenAudio").checked ? "include" : "exclude",
        selfBrowserSurface: "exclude",
        surfaceSwitching: "include",
      });
      if (generation !== stamp || !connected(r)) {
        acquired.forEach((t) => t.stop());
        return;
      }
      acquired.forEach((t) => localTracks.add(t));
      screenTracks = acquired;
      const video = acquired.find((t) => t.kind === sdk.Track.Kind.Video);
      video.mediaStreamTrack.addEventListener(
        "ended",
        () => {
          if (screenTracks.includes(video))
            void stopScreen(r).catch(() =>
              showError("屏幕采集已停止，但取消发布失败。"),
            );
        },
        { once: true },
      );
      for (const track of acquired) {
        await r.localParticipant.publishTrack(
          track,
          track.kind === sdk.Track.Kind.Video
            ? { ...options, source: sdk.Track.Source.ScreenShare }
            : publishAudio(
                cfg.media.screenAudio,
                sdk.Track.Source.ScreenShareAudio,
              ),
        );
        if (
          generation !== stamp ||
          !connected(r) ||
          !screenTracks.includes(track)
        ) {
          track.stop();
          await r.localParticipant.unpublishTrack(track);
          throw new Error("屏幕发布已中断。");
        }
      }
      message(
        "noticeMessage",
        $("includeScreenAudio").checked &&
          !acquired.some((t) => t.kind === sdk.Track.Kind.Audio)
          ? `屏幕已发布，请求编码 ${options.videoCodec.toUpperCase()}；未获取系统音轨，请检查浏览器选择器中的声音选项。`
          : `屏幕已发布，请求编码 ${options.videoCodec.toUpperCase()}；实际参数请查看统计。`,
      );
      refreshView();
    } catch (error) {
      if (generation === stamp && room === r) {
        await stopScreen(r).catch(() => {});
        showError(
          `屏幕共享失败：${error.name === "NotAllowedError" ? "权限被拒绝或选择已取消。" : "请检查采集权限、编码支持、设备负载与连接。"}`,
        );
      }
      acquired.forEach((t) => {
        localTracks.delete(t);
        t.stop();
      });
    } finally {
      if (generation === stamp) {
        screenBusy = false;
        updateButtons();
      }
    }
  }

  async function toggleMicrophone() {
    const r = room;
    const stamp = generation;
    if (!connected(r) || micBusy) return;
    micBusy = true;
    updateButtons();
    let acquired;
    try {
      if (micTrack) {
        if (micTrack.isMuted) await micTrack.unmute();
        else await micTrack.mute();
      } else {
        acquired = await sdk.createLocalAudioTrack(
          captureAudio(cfg.media.voice),
        );
        if (generation !== stamp || !connected(r)) {
          acquired.stop();
          return;
        }
        localTracks.add(acquired);
        micTrack = acquired;
        await r.localParticipant.publishTrack(
          acquired,
          publishAudio(cfg.media.voice, sdk.Track.Source.Microphone),
        );
        if (generation !== stamp || !connected(r)) {
          acquired.stop();
          await r.localParticipant.unpublishTrack(acquired);
          throw new Error("语音发布已中断。");
        }
      }
    } catch {
      if (acquired) {
        localTracks.delete(acquired);
        acquired.stop();
        await r.localParticipant.unpublishTrack(acquired).catch(() => {});
      }
      if (generation === stamp) {
        if (acquired) micTrack = null;
        showError(
          "语音操作失败，请检查麦克风权限、设备和发布权限；系统音轨不受此按钮影响。",
        );
      }
    } finally {
      if (generation === stamp) {
        micBusy = false;
        updateButtons();
      }
    }
  }

  async function collectStats() {
    if (statsBusy || !connected() || !viewedTrack) return;
    statsBusy = true;
    const track = viewedTrack;
    const stamp = generation;
    try {
      const outbound = track.isLocal;
      const endpoint = outbound ? track.sender : track.receiver;
      if (!endpoint?.getStats) {
        $("actualCodec").textContent = "浏览器未提供 RTP 统计";
        return;
      }
      const report = await endpoint.getStats();
      if (viewedTrack !== track || generation !== stamp) return;
      const codecs = new Set();
      const rows = [];
      const previous = new Map();
      let bitrate = 0;
      let hasRate = false;
      report.forEach((stat) => {
        if (
          stat.type !== (outbound ? "outbound-rtp" : "inbound-rtp") ||
          stat.isRemote ||
          (stat.kind && stat.kind !== "video")
        )
          return;
        const codec = report.get(stat.codecId)?.mimeType;
        if (
          codec?.toLowerCase().startsWith("video/") &&
          !/\/(rtx|red|ulpfec|flexfec)/i.test(codec)
        )
          codecs.add(codec);
        const bytes = outbound ? stat.bytesSent : stat.bytesReceived;
        const old = statsPrevious.get(stat.id);
        if (Number.isFinite(bytes)) {
          previous.set(stat.id, { bytes, time: stat.timestamp });
          if (old && stat.timestamp > old.time && bytes >= old.bytes) {
            bitrate +=
              ((bytes - old.bytes) * 8000) / (stat.timestamp - old.time);
            hasRate = true;
          }
        }
        if (stat.frameWidth && stat.frameHeight) {
          rows.push(
            `${stat.frameWidth} × ${stat.frameHeight}${Number.isFinite(stat.framesPerSecond) ? ` / ${stat.framesPerSecond.toFixed(1)} fps` : " / 帧率未报告"}`,
          );
        }
      });
      statsPrevious = previous;
      $("actualCodec").textContent = codecs.size
        ? [...codecs].join(", ")
        : "尚无编码统计（可能未被订阅）";
      $("actualResolution").textContent = rows.length
        ? [...new Set(rows)].join("; ")
        : "尚无画面统计";
      $("actualBitrate").textContent = hasRate
        ? `${(bitrate / 1000000).toFixed(2)} Mbps / ${outbound ? "主编码发送层合计" : "接收"}`
        : "等待下一次 RTP 采样";
    } catch {
      if (viewedTrack === track && generation === stamp)
        $("actualCodec").textContent = "统计暂不可用";
    } finally {
      statsBusy = false;
    }
  }

  function cleanup() {
    clearTimeout(moveTimer);
    clearInterval(heartbeatTimer);
    clearInterval(statsTimer);
    moveTimer = heartbeatTimer = statsTimer = null;
    clearReleaseTimers();
    controlEnabled = false;
    contacts.clear();
    screenTracks = [];
    micTrack = null;
    screenBusy = micBusy = false;
    for (const track of localTracks) track.stop();
    localTracks.clear();
    for (const track of [...audioNodes.keys()]) detachAudio(track);
    viewedTrack?.detach($("screenVideo"));
    viewedTrack = viewedPublication = null;
    viewedIdentity = "";
    $("screenVideo").pause();
    $("screenVideo").srcObject = null;
    $("screenPlaceholder").hidden = false;
    $("viewIdentity").textContent = "尚无屏幕";
    $("remoteParticipant").replaceChildren(
      new Option("选择远端参与者；未选择时显示本机预览", ""),
    );
    $("identity").textContent = "未连接";
    $("expiresAt").textContent = "未获取";
    $("controlSession").value = "连接后生成";
    $("joinKey").value = "";
    session = "";
    dirty = false;
    resetStats();
  }

  async function leaveRoom() {
    if (phase === "idle" || phase === "leaving") return;
    const stamp = ++generation;
    authAbort?.abort();
    authAbort = null;
    const r = room;
    const releasing = controlEnabled || contacts.size > 0;
    stopControl("已离开房间，触控会话失效。");
    phase = "leaving";
    setStatus("正在离开");
    updateButtons();
    // Let the three empty-snapshot retries run before shutting down the data channel.
    if (releasing && r?.state === sdk.ConnectionState.Connected)
      await new Promise((resolve) => setTimeout(resolve, 140));
    if (generation !== stamp) return;
    room = null;
    cleanup();
    try {
      if (r) await r.disconnect(true);
    } catch {
      showError("断开连接失败；本地轨道和音频节点已清理。");
    } finally {
      r?.removeAllListeners();
      if (generation === stamp) {
        phase = "idle";
        setStatus("未连接");
        updateButtons();
      }
    }
  }

  async function joinRoom(event) {
    event.preventDefault();
    if (!cfg || phase !== "idle") return;
    const name = $("roomName").value.trim();
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(name)) {
      showError("房间名格式无效。");
      return;
    }
    let key = $("joinKey").value;
    if (!key || /[\r\n]/.test(key)) {
      showError("请输入有效的加入密钥。");
      return;
    }
    const stamp = ++generation;
    let r;
    let credentials;
    phase = "joining";
    setStatus("正在认证");
    message("errorMessage", "");
    message("noticeMessage", "");
    updateButtons();
    const controller = new AbortController();
    authAbort = controller;
    const timeout = setTimeout(
      () => controller.abort(),
      cfg.transport.websocketTimeout,
    );
    try {
      const request = fetch("/api/session", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${key}`,
        },
        body: JSON.stringify({ room: name, node: $("nodeSelect").value }),
        cache: "no-store",
        credentials: "omit",
        redirect: "error",
        signal: controller.signal,
      });
      key = "";
      $("joinKey").value = "";
      const response = await request;
      if (!response.ok)
        throw new Error(
          response.status === 401 || response.status === 403
            ? "加入密钥无效或没有房间权限。"
            : `认证服务返回 HTTP ${response.status}。`,
        );
      credentials = await response.json();
      clearTimeout(timeout);
      if (generation !== stamp) return;
      if (
        typeof credentials.token !== "string" ||
        !credentials.token ||
        typeof credentials.identity !== "string" ||
        !credentials.identity
      )
        throw new Error("认证响应缺少令牌或身份。");
      const url = new URL(credentials.serverUrl);
      if (
        !["wss:", "ws:"].includes(url.protocol) ||
        url.username ||
        url.password ||
        (location.protocol === "https:" && url.protocol !== "wss:")
      )
        throw new Error("认证响应的 LiveKit WebSocket 地址无效或不安全。");
      r = new sdk.Room({
        adaptiveStream: cfg.media.adaptiveStream,
        dynacast: cfg.media.dynacast,
        // Keep encoding and scalability out of room defaults so later per-track choices
        // can genuinely remove a bitrate cap or switch from SVC to H.264/H.265.
        publishDefaults: {
          ...(supportedCodecs.length ? { videoCodec: chooseCodec() } : {}),
          simulcast: cfg.media.video.simulcast,
          backupCodec: false,
          audioPreset: { maxBitrate: cfg.media.voice.audioBitrate },
          dtx: cfg.media.voice.dtx,
          red: cfg.media.voice.red,
        },
        audioCaptureDefaults: captureAudio(cfg.media.voice),
        stopLocalTrackOnUnpublish: true,
        disconnectOnPageLeave: true,
      });
      room = r;
      bindRoom(r);
      setStatus("正在连接 LiveKit");
      const iceServers = Array.isArray(credentials.iceServers)
        ? credentials.iceServers
        : cfg.iceServers;
      await r.connect(url.href, credentials.token, {
        autoSubscribe: true,
        rtcConfig: {
          iceServers,
          iceTransportPolicy: cfg.transport.iceTransportPolicy,
          iceCandidatePoolSize: cfg.transport.iceCandidatePoolSize,
        },
        peerConnectionTimeout: cfg.transport.peerConnectionTimeout,
        websocketTimeout: cfg.transport.websocketTimeout,
        maxRetries: cfg.transport.maxRetries,
      });
      if (generation !== stamp || room !== r) {
        await r.disconnect(true);
        return;
      }
      phase = "connected";
      session = crypto.randomUUID();
      seq = 0;
      $("identity").textContent = r.localParticipant.identity;
      $("expiresAt").textContent =
        typeof credentials.expiresAt === "string" ||
        typeof credentials.expiresAt === "number"
          ? String(credentials.expiresAt)
          : "服务端未报告";
      $("controlSession").value = session;
      setStatus(`已连接 / ${$("nodeSelect").selectedOptions[0].textContent}`);
      for (const participant of r.remoteParticipants.values()) {
        for (const publication of participant.trackPublications.values())
          if (publication.track) attachTrack(publication.track);
      }
      refreshParticipants();
      statsTimer = setInterval(() => {
        if (controlEnabled && !validTarget())
          stopControl("屏幕或连接已失效，触控已停止。");
        updateButtons();
        void collectStats();
      }, 1000);
      message(
        "noticeMessage",
        "已加入。语音和触控默认关闭；如听不到声音，请点击“启用声音 / 播放”。",
      );
    } catch (error) {
      if (generation === stamp) {
        if (room === r) room = null;
        cleanup();
        if (r) {
          r.removeAllListeners();
          await r.disconnect(true).catch(() => {});
        }
        phase = "idle";
        setStatus("加入失败");
        const safeError =
          error.name === "AbortError"
            ? "认证超时或已取消。"
            : error instanceof SyntaxError
              ? "认证响应不是有效的 JSON。"
              : error instanceof TypeError
                ? "网络请求失败，请检查认证服务与 WebSocket 地址。"
                : error.message;
        // Do not render SDK error objects: they may contain connection URLs or credentials.
        showError(
          `加入失败：${r ? "请检查 LiveKit 地址、ICE 连通性、权限和服务端日志。" : safeError}`,
        );
      }
    } finally {
      clearTimeout(timeout);
      key = "";
      if (credentials) credentials.token = "";
      credentials = null;
      if (authAbort === controller) authAbort = null;
      updateButtons();
    }
  }

  $("joinForm").addEventListener("submit", joinRoom);
  $("leaveButton").addEventListener("click", () => void leaveRoom());
  $("shareButton").addEventListener("click", () => void shareScreen());
  $("micButton").addEventListener("click", () => void toggleMicrophone());
  $("remoteParticipant").addEventListener("change", () => {
    stopControl("目标已切换，请在原生端重新确认授权。");
    refreshView();
  });
  $("limitBitrate").addEventListener("change", () => {
    $("maxBitrate").disabled = !$("limitBitrate").checked;
  });
  $("maxBitrate").addEventListener("input", () => {
    $("bitrateValue").textContent = `${$("maxBitrate").value} Mbps`;
  });
  $("controlConsent").addEventListener("change", () => {
    if (!$("controlConsent").checked) stopControl("触控授权确认已取消。");
    updateButtons();
  });
  $("controlButton").addEventListener("click", () => {
    if (controlEnabled) {
      stopControl("触控已手动关闭。");
      return;
    }
    if (!validTarget() || !$("controlConsent").checked) return;
    controlEnabled = true;
    $("controlStatus").textContent =
      `仅向 ${viewedIdentity} 发送触控快照；网页不能确认原生端是否接受授权。`;
    updateButtons();
  });
  $("startPlaybackButton").addEventListener("click", () => {
    if (!connected()) return;
    const r = room;
    Promise.all([r.startAudio(), r.startVideo()])
      .then(() => {
        if (room === r) {
          message("noticeMessage", "已请求开启声音和画面播放。");
          updateButtons();
        }
      })
      .catch(() => showError("播放未获准，请检查浏览器自动播放权限。"));
  });
  $("fullscreenButton").addEventListener("click", () => {
    stopControl("视图尺寸正在切换，触控已停止。");
    const action = document.fullscreenElement
      ? document.exitFullscreen?.()
      : $("screenStage").requestFullscreen?.();
    if (!action) {
      message("noticeMessage", "此浏览器不支持元素全屏。");
      return;
    }
    action.catch(() => showError("浏览器拒绝全屏请求。"));
  });
  for (const event of ["loadeddata", "playing", "pause", "emptied"]) {
    $("screenVideo").addEventListener(event, () => {
      if (controlEnabled && !validTarget())
        stopControl("画面暂停或尚未就绪，触控已停止。");
      updateButtons();
    });
  }
  $("screenVideo").addEventListener("resize", () => {
    if (controlEnabled) stopControl("屏幕内容尺寸改变，请重新确认触控映射。");
    updateButtons();
  });
  window.addEventListener("blur", () => stopControl("窗口失焦，触控已停止。"));
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) stopControl("页面进入后台，触控已停止。");
  });
  window.addEventListener("resize", () => {
    if (controlEnabled) stopControl("视图布局改变，触控已停止。");
  });
  document.addEventListener("fullscreenchange", () => {
    if (controlEnabled) stopControl("全屏状态改变，触控已停止。");
  });
  window.addEventListener("pagehide", () => {
    generation += 1;
    authAbort?.abort();
    stopControl("页面关闭，触控已停止。");
    const r = room;
    room = null;
    cleanup();
    r?.removeAllListeners();
    if (r) void r.disconnect(true).catch(() => {});
    phase = "idle";
    setStatus("未连接");
    updateButtons();
  });

  async function initialize() {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);
    try {
      if (!sdk || sdk.version !== "2.23.0")
        throw new Error(
          "请提供本地固定版本 LiveKit SDK 2.23.0：/livekit-client.umd.js。",
        );
      if (
        !window.isSecureContext ||
        !sdk.isBrowserSupported() ||
        !crypto.randomUUID
      )
        throw new Error(
          "需要安全上下文（HTTPS / localhost）及支持 WebRTC、会话 UUID 的现代浏览器。",
        );
      const response = await fetch("/config.json", {
        cache: "no-store",
        credentials: "omit",
        redirect: "error",
        signal: controller.signal,
      });
      if (!response.ok)
        throw new Error(`配置加载失败：HTTP ${response.status}。`);
      const config = await response.json();
      if (
        !config ||
        typeof config.serverUrl !== "string" ||
        !Array.isArray(config.nodes)
      )
        throw new Error("/config.json 缺少 serverUrl 或 nodes。");
      if (
        !config.media?.video ||
        !config.media.screenAudio ||
        !config.media.voice ||
        !config.transport ||
        !config.control
      )
        throw new Error("/config.json 缺少集中调参配置。");
      cfg = {
        serverUrl: config.serverUrl,
        nodes: config.nodes,
        iceServers: Array.isArray(config.iceServers) ? config.iceServers : [],
        media: {
          adaptiveStream: config.media.adaptiveStream,
          dynacast: config.media.dynacast,
          video: { ...config.media.video },
          screenAudio: { ...config.media.screenAudio },
          voice: { ...config.media.voice },
        },
        transport: { ...config.transport },
        control: { ...config.control },
      };
      if (!Array.isArray(cfg.media.video.codecPriority))
        throw new Error("配置中的 codecPriority 必须为数组。");
      if (
        !/^(?:L1T[123]|L[23]T[123](?:h|_KEY)?)$/.test(
          cfg.media.video.scalabilityMode,
        )
      )
        throw new Error("配置中的 SVC scalabilityMode 无效。");
      for (const settings of [cfg.media.screenAudio, cfg.media.voice]) {
        if (
          !Number.isFinite(settings.audioBitrate) ||
          settings.audioBitrate < 6000 ||
          settings.audioBitrate > 510000
        )
          throw new Error("音频码率配置不在 Opus 有效范围内。");
      }
      cfg.control.sampleRate = Math.min(
        120,
        Math.max(1, Number(cfg.control.sampleRate) || 120),
      );
      cfg.control.maxContacts = Math.min(
        10,
        Math.max(1, Math.floor(Number(cfg.control.maxContacts) || 10)),
      );
      cfg.control.watchdogMs = Math.max(
        30,
        Number(cfg.control.watchdogMs) || 250,
      );
      if (typeof cfg.control.topic !== "string" || !cfg.control.topic)
        throw new Error("触控 topic 配置无效。");
      if (!["all", "relay"].includes(cfg.transport.iceTransportPolicy))
        throw new Error("ICE 传输策略必须为 all 或 relay。");
      for (const field of [
        "peerConnectionTimeout",
        "websocketTimeout",
        "iceCandidatePoolSize",
        "maxRetries",
      ]) {
        if (!Number.isFinite(cfg.transport[field]) || cfg.transport[field] < 0)
          throw new Error("连接超时、重试或 ICE 池配置无效。");
      }
      const names = new Set();
      for (const node of cfg.nodes) {
        if (
          !node ||
          typeof node.name !== "string" ||
          !node.name ||
          names.has(node.name)
        )
          throw new Error("节点名称为空或重复。");
        names.add(node.name);
        $("nodeSelect").add(
          new Option(
            `${node.name}${node.region ? ` / ${node.region}` : ""}`,
            node.name,
          ),
        );
      }
      supportedCodecs = codecCapabilities().filter(
        (codec) =>
          cfg.media.video.codecPriority.includes(codec) || codec === "h264",
      );
      for (const codec of supportedCodecs)
        $("codecSelect").add(new Option(codec.toUpperCase(), codec));
      $("codecSupport").textContent = supportedCodecs.length
        ? `本机双向能力（配置范围内）：${supportedCodecs.map((c) => c.toUpperCase()).join(" / ")}。自动优先级：${cfg.media.video.codecPriority.join(" > ")}；无匹配则回退 H.264。`
        : "无法确认双向视频编码能力，可加入观看，但屏幕发布已禁用。";
      if ([1080, 1440, 2160].includes(cfg.media.video.height))
        $("resolution").value = String(cfg.media.video.height);
      if ([60, 120].includes(cfg.media.video.frameRate))
        $("frameRate").value = String(cfg.media.video.frameRate);
      if (["detail", "motion"].includes(cfg.media.video.contentHint))
        $("contentHint").value = cfg.media.video.contentHint;
      if (
        Number.isFinite(cfg.media.video.maxBitrate) &&
        cfg.media.video.maxBitrate > 0
      ) {
        $("limitBitrate").checked = true;
        $("maxBitrate").value = String(
          Math.min(
            80,
            Math.max(1, Math.ceil(cfg.media.video.maxBitrate / 1000000)),
          ),
        );
        $("maxBitrate").disabled = false;
        $("bitrateValue").textContent = `${$("maxBitrate").value} Mbps`;
      }
      $("audioSettings").textContent =
        `系统声音：${cfg.media.screenAudio.audioBitrate / 1000} kbps，DTX ${cfg.media.screenAudio.dtx ? "开" : "关"} / RED ${cfg.media.screenAudio.red ? "开" : "关"}。独立语音：${cfg.media.voice.audioBitrate / 1000} kbps，DTX ${cfg.media.voice.dtx ? "开" : "关"} / RED ${cfg.media.voice.red ? "开" : "关"}；降噪与回声处理按服务端配置请求。`;
      $("controlSettings").textContent =
        `topic: ${cfg.control.topic} / 移动合并上限 ${cfg.control.sampleRate} Hz / 按住时完整快照间隔 ≤ ${Math.min(75, cfg.control.watchdogMs / 3).toFixed(0)} ms / 原生看门狗 ${cfg.control.watchdogMs} ms / 最多 ${cfg.control.maxContacts} 点`;
      setStatus("未连接");
    } catch (error) {
      cfg = null;
      setStatus("配置不可用");
      showError(
        error.name === "AbortError"
          ? "配置请求超时，请刷新页面重试。"
          : error.message,
      );
    } finally {
      clearTimeout(timeout);
      updateButtons();
    }
  }

  void initialize();
})();
