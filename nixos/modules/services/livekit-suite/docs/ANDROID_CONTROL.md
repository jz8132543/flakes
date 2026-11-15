# Android 屏幕与触控控制

本文配套 `../android-control.py` 和 `../test-android-control.py`。守护进程只使用 Python 标准库，可在 Termux 中运行；默认后端是 Root `/dev/uinput`，另有功能有限的 Shizuku shell 降级模式。它不是 Android 屏幕采集应用，也不是 LiveKit 服务端插件。此目录的新增文件不会自动部署、启动或修改现有 Nix 服务。

## 能力与边界

- 屏幕视频由原生 Android 应用使用 MediaProjection、LiveKit Android SDK 和 WebRTC 编码发布。用户必须在 Android 系统对话框中授权；服务端不能替设备启用采集。Termux Python、Root 注入和 Shizuku 授权均不能替代原生 MediaProjection 生命周期及授权。
- 触控路径为：控制端完整触点快照 → LiveKit lossy 数据包 → Android 原生应用验证发送者与本地授权 → 本机 HTTP → Root uinput。HTTP 始终绑定 `127.0.0.1`，不提供公网端口、UDP 输入端口或任意 shell 执行接口。
- Root 模式支持 1 至 10 点、Type B slots、独立 tracking ID、`BTN_TOUCH`、`SYN_REPORT`、坐标旋转和 ABS 范围。是否被 Android InputReader 正确识别及映射到目标显示器，需要真机验证；成功创建 uinput 不等于已经验证触屏行为。
- Shizuku 本身不能创建 `/dev/uinput`，也没有可由普通 Python 直接调用的官方注入 API。非 Root Shizuku 一般使用 shell UID 2000，不是 UID 0。本文 shell 降级模式经授权 `rish` 执行 `/system/bin/input`，不是 Python Binder API。
- **不承诺零延迟或确定性 120Hz。** 视频采集、编码、网络、解码、显示、Binder/InputReader、HTTP 和调度都增加延迟；120Hz 只是触控快照发送目标。应测量触控到画面反馈的 p50/p95/p99，而不只是网络 RTT。
- **不能强制设备使用不支持的 AV1/HEVC 硬件。** `MediaCodecList`、SDK 所打包的 WebRTC 编解码器、实际协商、发送端编码器和接收端解码器都必须支持所选格式。仅配置服务端 codec 列表不会产生硬件支持；HEVC 也并非所有 Android LiveKit/WebRTC 版本都可用。先用双方实测可用且 SFU 允许的 H.264，再按协商与编码统计选择格式；VP8 仅在 SFU 也启用时才是候选，不是所有部署的默认回退。支持 AV1 解码不代表支持 AV1 硬件编码。

## Root 启动

使用可信来源的 Termux，安装 Python，将 `android-control.py` 放在 Termux 私有目录，不要从共享存储运行需要 Root 权限的可写脚本。以下命令在 Termux 中执行，假定脚本路径是 `$HOME/android-control.py`：

```sh
pkg install python
mkdir -p "$HOME/.android-control"
chmod 700 "$HOME/.android-control"
su -c '/system/bin/id -u'
su -c '/system/bin/wm size'
su -c '/system/bin/wm density'
su -c '/system/bin/ls -l /dev/uinput /dev/input/uinput'
su -c '/system/bin/getevent -lp'
```

`id -u` 必须返回 `0`。通常使用 `/dev/uinput`，有些设备需传 `--uinput /dev/input/uinput`。缺少设备节点、内核未启用 `CONFIG_INPUT_UINPUT`、SELinux 拒绝、Root 管理器未授权或内核缺少 uinput API 5 时，程序会拒绝启动；不会假装注入成功。不要对设备节点执行 `chmod 666`，不要为了启动服务关闭 SELinux。

下面以原生方向 1080×2400 的主显示器为例：

```sh
su -c "$PREFIX/bin/python -B '$HOME/android-control.py' --width 1080 --height 2400 --rotation 0 --token-file '$HOME/.android-control/runtime.token'"
```

保持前台运行，`Ctrl-C` 或 `SIGTERM` 会释放触点、销毁虚拟输入设备并删除本次 token 文件。Root shell 的环境取决于 Root 管理器和 Termux 版本；若 Python 找不到共享库，应使用可信 Termux 的实际 `$PREFIX` 并检查 Root 启动环境，而不是改用共享存储中的 Python。守护进程无第三方 Python 依赖。

每次启动产生 32 字节随机 token，写入新建的 `0600` 文件，父目录必须为私有目录（如 `0700`）。终端只打印文件位置，不打印 token。将 token **经可信本机配对流程**交给原生桥接应用，例如设备所有者在本机读取后手动输入到应用的私有设置界面：

```sh
su -c "cat '$HOME/.android-control/runtime.token'"
```

该操作会将秘密显示在本机终端；注意终端历史、录屏、剪贴板和肩窥。应用保存在私有存储，不写 logcat，不通过 LiveKit、房间 metadata、控制网页或公网 API 传递。文件由 Root 创建，普通 Android 应用不能直接读取。进程异常死亡可能留下旧文件；确认旧进程已停止后才删除该文件并重启。启动不会复用或覆盖旧 token 文件，重启必须重新配对。

Root 服务执行的是高权限输入。回环地址不是应用隔离：同设备其他应用也可能连接该端口，因此 token 仍然必需。同 UID、Root、被入侵的桥接应用以及可修改脚本/配对材料的攻击者不在该隔离模型内。不要做端口转发、反向代理、ADB TCP 转发或公开监听；这里不提供 TLS，因为连接不应离开设备。

### 坐标与旋转

协议坐标来自**当前屏幕画面内容**，左上 `(0,0)`，右下 `(1,1)`；不包含播放器黑边、容器 padding 或裁剪外区域。默认 ABS 范围为 `0..width-1`、`0..height-1`，可用 `--x-min/--x-max/--y-min/--y-max` 明确指定其他非负范围，最大为有符号 32 位整数。

Root 模式的 `--width/--height` 使用虚拟设备原生方向的逻辑尺寸，不要把 `getevent` 的原始触屏轴最大值误当像素数。`wm size` 的 override、显示缩放、外接屏和 Android viewport 映射会影响效果，必须检查四角和中心位置。

`--rotation` 表示显示相对原生方向顺时针旋转的角度，程序进行如下逆变换，然后缩放至 ABS 范围：

| 角度 | 画面 `(x,y)` → 原生 ABS 归一化坐标 |
| ---- | ---------------------------------- |
| 0    | `(x,y)`                            |
| 90   | `(y,1-x)`                          |
| 180  | `(1-x,1-y)`                        |
| 270  | `(1-y,x)`                          |

Android 还可能依据输入设备配置（IDC）、`touch.orientationAware` 和 display viewport 再做旋转/缩放。必须验证实际 InputReader 映射，不能未经验证叠加两次相同旋转。可先固定显示方向与采集方向；改变方向或显示器时，在应用撤销授权、停止发送并重启守护进程以更新参数，再发新授权。程序没有实时获取 Android 显示配置，也不自动选择外接显示器。

可在另一个 Root 终端用 `getevent -lp` 查找名为 `LiveKit Android Touch` 的设备，再观察其事件和 `dumpsys input`。它声明直接触屏属性，Type B 槽范围为 0..9；每次新增触点分配 tracking ID，移除时发送 `-1`。Root/ioctl 检测仅验证内核接口，不绕过 Android 设备分类、SELinux、ROM 限制或屏幕锁定策略。

## 完整状态协议

LiveKit topic 固定为 `control.touch.v1`。每包必须是 UTF-8 JSON：

```json
{
  "v": 1,
  "session": "12345678-1234-4234-8234-123456789abc",
  "seq": 0,
  "type": "snapshot",
  "points": [{ "id": 0, "x": 0.25, "y": 0.75 }]
}
```

- `session` 是每次本地授权绑定的新 UUID，小写、带连字符。可由设备生成，也可由控制网页生成后经设备所有者本地确认；必须先授权，再发送，收到第一个包不会自动授权或更换 session。
- `seq` 是非负整数，严格递增；为与 JS 精确整数一致，上限 `9007199254740991`。允许跳号，拒绝重复和小于高水位的包。页面重载、重连或计数归零需要设备端显式重置/重新授权，不允许靠数据包抢占 session。
- `type` 只能是 `snapshot`，没有 `down`、`move`、`up` 或 `cancel` 类型。每次事件均表示**全部当前活跃触点**，不是增量。触点 ID 是稳定的 0..9 小整数，不是任意浏览器 `pointerId`。
- 多点抬起一根手指时，只移除该手指，其他活跃触点仍在 `points`。**最后一个 up 为 `points:[]`；cancel 清空全部触点，也发送 `points:[]`。** 非法坐标、重复 ID、布尔数值、NaN/Infinity、未知/缺失字段和重复 JSON key 均拒绝。
- 按住期间，无论是否移动，持续以目标 120Hz 发送完整快照。移动可合并为最新坐标；down/up/cancel 的状态边沿应立即发送完整快照。边沿瞬时可能超过 120 包/秒，这不是硬实时节流器。
- 采用不可靠数据传输以避免可靠重传队列带来的延迟。丢掉 down 后，下一个按住快照可建立触点；丢掉某一手指的 up 后，下一个完整快照会移除该指。所有释放包均丢失时，由看门狗兜底。

守护进程使用本机单调时钟：有触点且连续 **250ms 未收到有效、更新序号的完整快照**就发送全部 release。独立线程每 10ms 检查，慢 HTTP 读不会阻止看门狗。无效、错误 session、重复或过期序号不会刷新计时。看门狗保留当前授权 session 和序号高水位；授权 TTL 到期则释放并撤销。正常 []、reset、revoke 和正常退出也释放。

250ms 是释放策略，不是绝对时限保证：进程暂停、内核失败、系统过载或被强杀时不保证及时执行。序号只防已见过的旧包；协议没有发送时间戳，未见过的高序号延迟包仍可能重新建立短暂触点。因此接收应用应丢弃本地排队过久的数据，撤权和重连要换 session；不能把看门狗称为端到端实时安全保证。

## 本机 HTTP

只有 HTTP POST 被支持，所有端点都要求：

```text
Authorization: Bearer <本次运行 token>
Content-Type: application/json
Content-Length: <字节数，1..4096>
```

不接受 chunked、重复鉴权/长度头，也不提供 CORS。带 `Origin` 的请求拒绝，浏览器应经 LiveKit 发包，而不是直接调用设备 HTTP。每次响应关闭连接；请求读超时为 500ms。监听 IPv4 `127.0.0.1`，不监听 `::` 或 `0.0.0.0`；程序没有 `--host` 参数。

| POST 路径   | JSON 内容                                                                       | 作用                                                                            |
| ----------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `/grant`    | `{"session":"<新 UUID>","controller":"<可信 LiveKit identity>","ttl_ms":60000}` | 本地已同意后绑定一个控制者，TTL 1..3600000ms；已有授权则 409，不允许静默替换    |
| `/snapshot` | 上述完整协议包                                                                  | 只接收当前已授权 session，严格递增 seq                                          |
| `/reset`    | `{"session":"<当前 UUID>","new_session":"<新 UUID>"}`                           | 释放全部触点，更换 session，seq 高水位重置为 -1；保留控制者和原 TTL，不延长授权 |
| `/revoke`   | `{"session":"<当前 UUID>"}`                                                     | 释放并撤销授权；旧控制包不再有效                                                |
| `/status`   | `{}`                                                                            | 返回当前 session、controller、seq、活跃数和剩余 TTL，不返回 token               |

响应为 JSON，成功为 200。常见失败为 400 载荷错误、401 token 错误、403 未授权 session、409 旧序号/已有授权/已用 UUID、413 过大、415 内容类型错误、422 后端触点数不支持、429 shell 手势繁忙、503 输入后端故障。输入 I/O 故障会撤权、销毁设备并停止守护进程，不能继续假装成功。

`controller` 是由可信本机应用记录的授权审计属性，**Python 不验证 LiveKit 身份**。拥有本机 bearer token 就能调用授权端点。因此身份认证必须在原生 LiveKit 回调中完成，不能让远端数据包里的字符串决定控制者。运行期不重复使用已用过的 UUID（最多 4096 个）；重启会清空此记录，但也更换 bearer token，仍须重新本地授权。

## 控制端示例

下面使用 LiveKit JS SDK 的 `room.localParticipant.publishData`。`reliable:false`、`topic:'control.touch.v1'`、`destinationIdentities:[target]` 都要设置。`target` 是目标设备的 LiveKit identity，不是房间名或 SID。该函数在目标设备本地授权后才调用，传入由设备返回的新 session；不要把本机 HTTP token 给网页。

```typescript
import { Room } from "livekit-client";

export function attachTouchControl(
  video: HTMLVideoElement,
  room: Room,
  target: string,
  session: string,
  reportFailure: (error: unknown) => void,
) {
  const active = new Map<number, { id: number; x: number; y: number }>();
  let seq = 0;
  let releaseRepeats = 0;
  let closed = false;
  const previousTouchAction = video.style.touchAction;
  video.style.touchAction = "none";

  function position(event: PointerEvent, clamp: boolean) {
    const rect = video.getBoundingClientRect();
    if (!video.videoWidth || !video.videoHeight || !rect.width || !rect.height)
      return null;
    // Assumes object-fit: contain, no border/padding, and no cropped/mirrored video.
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
    if (!clamp && (x < 0 || x > 1 || y < 0 || y > 1)) return null;
    return { x: Math.max(0, Math.min(1, x)), y: Math.max(0, Math.min(1, y)) };
  }

  function publish() {
    if (closed) return;
    if (seq > Number.MAX_SAFE_INTEGER) {
      active.clear();
      closed = true;
      reportFailure(new Error("sequence exhausted; local reset required"));
      return;
    }
    const bytes = new TextEncoder().encode(
      JSON.stringify({
        v: 1,
        session,
        seq: seq++,
        type: "snapshot",
        points: [...active.values()],
      }),
    );
    // Do not maintain a retry/backlog queue for lossy touch updates.
    void room.localParticipant
      .publishData(bytes, {
        reliable: false,
        topic: "control.touch.v1",
        destinationIdentities: [target],
      })
      .catch(reportFailure);
  }

  function cancel() {
    active.clear();
    releaseRepeats = 3;
    publish();
  }

  function down(event: PointerEvent) {
    if (
      closed ||
      document.hidden ||
      active.has(event.pointerId) ||
      active.size >= 10
    )
      return;
    if (event.pointerType === "mouse" && event.button !== 0) return;
    const point = position(event, false);
    if (!point) return;
    const used = new Set([...active.values()].map((point) => point.id));
    const id = Array.from({ length: 10 }, (_, id) => id).find(
      (id) => !used.has(id),
    )!;
    active.set(event.pointerId, { id, ...point });
    video.setPointerCapture(event.pointerId);
    releaseRepeats = 0;
    event.preventDefault();
    publish();
  }

  function move(event: PointerEvent) {
    const contact = active.get(event.pointerId);
    const point = position(event, true);
    if (contact && point) {
      active.set(event.pointerId, { id: contact.id, ...point });
      event.preventDefault();
    }
  }

  function up(event: PointerEvent) {
    if (!active.delete(event.pointerId)) return;
    if (video.hasPointerCapture(event.pointerId))
      video.releasePointerCapture(event.pointerId);
    if (!active.size) releaseRepeats = 3;
    event.preventDefault();
    publish(); // Other active fingers remain; only the last up sends [].
  }

  function lost(event: PointerEvent) {
    if (active.has(event.pointerId)) cancel();
  }

  function visibility() {
    if (document.hidden) cancel();
  }
  video.addEventListener("pointerdown", down);
  video.addEventListener("pointermove", move);
  video.addEventListener("pointerup", up);
  video.addEventListener("pointercancel", cancel);
  video.addEventListener("lostpointercapture", lost);
  window.addEventListener("blur", cancel);
  document.addEventListener("visibilitychange", visibility);
  const timer = window.setInterval(() => {
    if (active.size || releaseRepeats > 0) {
      publish(); // Includes stationary held contacts and a short [] release burst.
      if (!active.size) releaseRepeats--;
    }
  }, 1000 / 120);

  return () => {
    cancel();
    closed = true;
    window.clearInterval(timer);
    video.removeEventListener("pointerdown", down);
    video.removeEventListener("pointermove", move);
    video.removeEventListener("pointerup", up);
    video.removeEventListener("pointercancel", cancel);
    video.removeEventListener("lostpointercapture", lost);
    window.removeEventListener("blur", cancel);
    document.removeEventListener("visibilitychange", visibility);
    video.style.touchAction = previousTouchAction;
  };
}
```

浏览器计时器会抖动、后台会被节流；隐藏/失焦即清空，守护进程仍靠看门狗兜底。若视频被旋转、镜像或裁剪，需要先把坐标映射回实际采集画面再调用此逻辑；此示例明确限定为非镜像、非裁剪的 `object-fit:contain`。短促点击包仍可能丢失，这是 lossy 的实际限制，不可宣称每次点击必达。

## 原生 LiveKit Android 接收桥

以下 Kotlin 使用已核对源码的 `io.livekit:livekit-android:2.23.1` API，以及 AndroidX 和 kotlinx-coroutines。生产应用应锁定并测试自己的 SDK 版本，不能直接把 JS 参数名照搬到 Kotlin。2.23.1 的 `RoomEvent.DataReceived` 有 `data`、`participant`、`topic`，发送端使用 `DataPublishReliability.LOSSY` 和 `identities: List<Participant.Identity>`。较新版本可能新增 `participantIdentity` 等字段；本例仍要求非空的真实房间 participant，拒绝无法对应当前连接的服务端/已离开参与者数据，不以 payload 或新增字符串字段作为授权凭据。

后台签发 LiveKit JWT 时，应认证登录用户、限制允许加入的房间、绑定不可任意选择的唯一 identity，并仅授予需要的 publish-data 权限。JWT 签名验证由 LiveKit 处理；原生应用再做本地控制授权。**能进入房间或发送数据不等于有控制权。** 不信任 participant metadata 中自行声明的管理员角色。

本例绑定 identity **和当前 participant SID**，TTL 最多 60 秒，单个授权 session。`grantAfterLocalApproval` 只能由设备所有者明确同意、或可信后台授权加本地策略同意的 UI 流程调用；不能从 `DataReceived`、任意 RPC 参数、未验证网页或远端自报 identity 直接调用。默认由设备生成 session，也可在本地确认 identity 和网页显示的新 UUID 后传入 `approvedSession`，以接入展示 UUID 的现有控制网页；UUID 本身不是授权凭据。将该方法返回的 session 通过已认证的授权流程只交给相应控制者。

```kotlin
import android.os.SystemClock
import io.livekit.android.events.RoomEvent
import io.livekit.android.events.collect
import io.livekit.android.room.Room
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

class AndroidTouchBridge(
    private val room: Room,
    private val bearerToken: String,
    private val port: Int = 8765,
    private val reportFailure: (String) -> Unit,
) {
    private data class Grant(
        val identity: String, val sid: String, val session: String, val expiresAt: Long,
    )
    private data class Frame(
        val identity: String, val sid: String, val data: ByteArray, val receivedAt: Long,
    )
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutex = Mutex()
    private val incoming = Channel<Frame>(Channel.CONFLATED)
    private var grant: Grant? = null

    init {
        require(port in 1..65535)
        require(bearerToken.matches(Regex("[A-Za-z0-9_-]{43}")))
        scope.launch {
            room.events.collect { event ->
                when (event) {
                    is RoomEvent.DataReceived -> {
                        val sender = event.participant
                        val identity = sender?.identity?.value
                        val receivedAt = SystemClock.elapsedRealtime()
                        if (event.topic == "control.touch.v1" && sender != null &&
                            identity != null && event.data.size in 1..4096) {
                            // Reject unapproved senders BEFORE they can replace the conflated frame.
                            mutex.withLock {
                                val current = grant
                                if (current != null && identity == current.identity &&
                                    sender.sid.value == current.sid &&
                                    SystemClock.elapsedRealtime() < current.expiresAt) {
                                    incoming.trySend(Frame(identity, sender.sid.value,
                                        event.data.copyOf(), receivedAt))
                                }
                            }
                        }
                    }
                    is RoomEvent.ParticipantDisconnected -> mutex.withLock {
                        if (grant?.sid == event.participant.sid.value) revokeLocked()
                    }
                    is RoomEvent.Disconnected, is RoomEvent.Reconnecting ->
                        mutex.withLock { revokeLocked() }
                    else -> Unit
                }
            }
        }
        scope.launch {
            for (frame in incoming) {
                mutex.withLock {
                    val current = grant
                    val now = SystemClock.elapsedRealtime()
                    if (current != null && now >= current.expiresAt) revokeLocked()
                    else if (current != null && frame.identity == current.identity &&
                        frame.sid == current.sid && now - frame.receivedAt <= 100) {
                        val session = try {
                            JSONObject(String(frame.data, Charsets.UTF_8)).optString("session")
                        } catch (_: Exception) { "" }
                        if (session == current.session) {
                            try {
                                val status = post("/snapshot", frame.data)
                                // Stale/invalid packets do not refresh the daemon watchdog.
                                if (status !in setOf(200, 400, 403, 409, 422, 429)) {
                                    revokeLocked()
                                    reportFailure("Touch backend rejected request: HTTP $status")
                                }
                            } catch (error: CancellationException) {
                                throw error
                            } catch (_: IOException) {
                                revokeLocked()
                                reportFailure("Local touch bridge unavailable; control revoked")
                            }
                        }
                    }
                }
            }
        }
        scope.launch {
            while (true) {
                delay(100)
                mutex.withLock {
                    val current = grant
                    if (current != null && SystemClock.elapsedRealtime() >= current.expiresAt) {
                        revokeLocked()
                    }
                }
            }
        }
    }

    suspend fun grantAfterLocalApproval(
        trustedIdentity: String,
        approvedSession: String = UUID.randomUUID().toString(),
        ttlMs: Int = 60_000,
    ): String =
        mutex.withLock {
            require(ttlMs in 1..60_000)
            require(UUID.fromString(approvedSession).toString() == approvedSession)
            val old = grant
            if (old != null && SystemClock.elapsedRealtime() >= old.expiresAt) revokeLocked()
            check(grant == null) { "Explicit revoke/reset required" }
            val participant = room.remoteParticipants.values.singleOrNull {
                it.identity?.value == trustedIdentity
            } ?: error("Approved controller is not currently in this room")
            val session = approvedSession
            val startedAt = SystemClock.elapsedRealtime()
            val payload = JSONObject().put("session", session).put("controller", trustedIdentity)
                .put("ttl_ms", ttlMs).toString().toByteArray(Charsets.UTF_8)
            if (post("/grant", payload) != 200) throw IOException("Local grant rejected")
            grant = Grant(trustedIdentity, participant.sid.value, session, startedAt + ttlMs)
            session
        }

    suspend fun resetAfterLocalApproval(): String = mutex.withLock {
        val old = checkNotNull(grant) { "No control grant" }
        check(SystemClock.elapsedRealtime() < old.expiresAt) { "Grant expired" }
        val replacement = UUID.randomUUID().toString()
        val payload = JSONObject().put("session", old.session).put("new_session", replacement)
            .toString().toByteArray(Charsets.UTF_8)
        if (post("/reset", payload) != 200) {
            revokeLocked()
            throw IOException("Local reset rejected")
        }
        grant = old.copy(session = replacement)
        replacement // Deliver through the authenticated grant flow, then sender starts seq=0.
    }

    suspend fun revokeAfterLocalDecision() = mutex.withLock { revokeLocked() }

    private suspend fun revokeLocked() {
        val old = grant ?: return
        grant = null // Stop forwarding even if HTTP fails or the daemon already expired the grant.
        try {
            val payload = JSONObject().put("session", old.session).toString().toByteArray(Charsets.UTF_8)
            val status = post("/revoke", payload)
            if (status != 200 && status != 403) reportFailure("Local revoke failed; watchdog/TTL remain active")
        } catch (error: CancellationException) {
            throw error
        } catch (_: IOException) {
            reportFailure("Local revoke unavailable; watchdog/TTL remain active")
        }
    }

    private suspend fun post(path: String, bytes: ByteArray): Int = withContext(Dispatchers.IO) {
        val connection = URL("http://127.0.0.1:$port$path").openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 200
            connection.readTimeout = 200
            connection.doOutput = true
            connection.setRequestProperty("Authorization", "Bearer $bearerToken")
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setFixedLengthStreamingMode(bytes.size)
            connection.outputStream.use { it.write(bytes) }
            val status = connection.responseCode
            if (status == 200) connection.inputStream.use { it.readBytes() }
            else connection.errorStream?.close()
            status
        } finally { connection.disconnect() }
    }

    suspend fun stop() {
        try {
            withContext(NonCancellable) { mutex.withLock { revokeLocked() } }
        } finally {
            incoming.close()
            scope.cancel()
        }
    }
}
```

`reportFailure` 在 IO 线程调用，应用要切换到主线程显示错误，不记录 bearer/payload。桥接仅持有最新一个已授权帧，转发前再次核对 identity、SID、session、TTL 和本地排队年龄；daemon 最终严格校验全部字段及序号。Conflation 会丢中间快照，尤其是很短的 down/up；这与 lossy 同样是明确的权衡，并不承诺点击可靠性。授权、reset、revoke 与转发通过同一个 mutex 串行，避免旧授权的排队包污染新授权。

生命周期退出、设备锁定、用户按停止控制、控制者离房和连接重建应立即调用撤权/`stop()`。进程死亡后的释放依赖 daemon 看门狗与 TTL。屏幕停止采集也应撤权，不能在用户认为分享已结束后继续注入。授予/重置 HTTP 超时可能发生「请求已成功但响应丢失」；此时应停止发送，用本机 `/status` 确认并撤销残留 session 后再经本地授权重试，不能自动凭远端包恢复权限。

Android 原生控制端发送同一 JSON 时，2.23.1 的对应 API 是：

```kotlin
import io.livekit.android.room.Room
import io.livekit.android.room.participant.Participant
import io.livekit.android.room.track.DataPublishReliability

suspend fun publishTouch(room: Room, target: String, utf8Snapshot: ByteArray): Result<Unit> =
    room.localParticipant.publishData(
        data = utf8Snapshot,
        reliability = DataPublishReliability.LOSSY,
        topic = "control.touch.v1",
        identities = listOf(Participant.Identity(target)),
    )
```

### 本机 HTTP 的 Android 网络权限

原生应用需要 `android.permission.INTERNET`。对于默认禁止明文 HTTP 的 target SDK，使用只允许回环地址的 Network Security Config，不要全局开启任意明文流量。例如应用自己的 manifest 和资源配置应包含以下内容（本文仅示例，不会替应用创建文件）：

```xml
<!-- AndroidManifest.xml: application 的属性，合并到应用自己的 manifest -->
<application android:networkSecurityConfig="@xml/control_network_security" />
```

```xml
<!-- res/xml/control_network_security.xml -->
<network-security-config>
    <base-config cleartextTrafficPermitted="false" />
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">127.0.0.1</domain>
    </domain-config>
</network-security-config>
```

应用其余 HTTPS/WSS 设置及 SDK manifest 合并保持不变。不同 target SDK/Android 版本可能还引入本地网络访问限制，应在目标设备验证连接。连接地址必须和 daemon 一致，使用 `127.0.0.1` 而不是可能解析成 IPv6 的 `localhost`。

## MediaProjection 与原生采集

LiveKit Android 2.23.1 提供 `setScreenShareEnabled(enabled, ScreenCaptureParams)`，不是浏览器 `getDisplayMedia()`，也不是服务端的采集开关。最小权限交接示例：

```kotlin
import android.app.Activity
import android.app.Notification
import android.content.Context
import android.media.projection.MediaProjectionManager
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.lifecycleScope
import io.livekit.android.room.Room
import io.livekit.android.room.track.screencapture.ScreenCaptureParams
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

class ScreenShareConsent(
    private val activity: ComponentActivity,
    private val room: Room,
    private val ongoingNotification: Notification,
    private val onStopped: () -> Unit,
) {
    // Construct before the Activity reaches STARTED (for example, in onCreate).
    private val launcher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { result ->
        val permissionData = result.data
        if (result.resultCode == Activity.RESULT_OK && permissionData != null) {
            activity.lifecycleScope.launch {
                try {
                    val enabled = room.localParticipant.setScreenShareEnabled(
                        true,
                        ScreenCaptureParams(
                            mediaProjectionPermissionResultData = permissionData,
                            notificationId = 7001,
                            notification = ongoingNotification,
                            onStop = onStopped,
                        ),
                    )
                    if (!enabled) onStopped()
                } catch (error: CancellationException) {
                    onStopped()
                    throw error
                } catch (_: Exception) { onStopped() }
            }
        } else onStopped()
    }

    fun requestFromVisibleActivity() {
        val manager = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE)
            as MediaProjectionManager
        launcher.launch(manager.createScreenCaptureIntent())
    }
}
```

应用须创建有效 notification channel 和持续分享通知，处理 SDK 停止回调、拒绝授权、前后台切换和服务生命周期；`onStopped` 应撤销上述触控授权。不要在回调中吞掉协程取消后继续采集。此片段只演示授权 Intent 交接，未包含完整 Activity、通知 UI 或 LiveKit 登录应用，也不声称 Python 能完成这些原生职责。

2.23.1 SDK manifest 声明 `io.livekit.android.room.track.screencapture.ScreenCaptureService`、`foregroundServiceType="mediaProjection"`、`FOREGROUND_SERVICE` 和 `FOREGROUND_SERVICE_MEDIA_PROJECTION`，仍须检查应用 manifest 合并及 target SDK 的约束。Android 14+ 要遵守每次采集的新授权、前台服务启动顺序、单次 token/VirtualDisplay 限制和停止回调；系统可撤销采集，不能复用上次 Intent 偷偷恢复。Android 13+ 通知权限、麦克风录音权限、内部音频 AudioPlaybackCapture 的限制以及 `FLAG_SECURE` 内容不可采集也要独立处理。

### AV1/HEVC 硬件能力与发布配置

Android 10+ 可先枚举 SoC 实际暴露的硬件编码器。该检查还不能代替 SDK 支持检查和远端解码能力协商：

```kotlin
import android.media.MediaCodecList
import android.os.Build
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.Q)
fun hardwareScreenEncoders(width: Int, height: Int, fps: Int): Map<String, List<String>> {
    require(width > 0 && height > 0 && fps > 0)
    val all = MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos
    return listOf("video/av01", "video/hevc", "video/x-vnd.on2.vp9", "video/avc")
        .associateWith { mime ->
            all.filter { info ->
                if (!info.isEncoder || !info.isHardwareAccelerated || info.isAlias ||
                    !info.supportedTypes.any { it.equals(mime, ignoreCase = true) }) false
                else try {
                    info.getCapabilitiesForType(mime).videoCapabilities
                        .areSizeAndRateSupported(width, height, fps.toDouble())
                } catch (_: IllegalArgumentException) { false }
            }.map { it.name }
        }
}
```

系统 `video/av01` 对应 LiveKit `av1`，`video/hevc` 对应 `h265`。从 `/config.json` 读取视频优先级，依次与硬件能力、当前 WebRTC EncoderFactory 支持和订阅端能力求交集；不要只凭解码能力选编码。库没有暴露 HEVC 编码时，即使系统 MediaCodec 有 HEVC 也不能通过字符串开启它。

在原生采集启动**之前**设置已确认可用的发布偏好。这里参数由服务配置传入，不把 JS 的 `forceStereo`/`screenShareEncoding` 直接照搬到 Android：

```kotlin
import io.livekit.android.room.Room
import io.livekit.android.room.participant.BackupVideoCodec
import io.livekit.android.room.participant.VideoTrackPublishDefaults

fun preferScreenCodec(room: Room, supportedCodec: String, supportedBackup: String?) {
    require(supportedCodec in setOf("av1", "h265", "vp9", "h264"))
    require(supportedBackup == null || supportedBackup == "h264")
    room.localParticipant.screenShareTrackPublishDefaults = VideoTrackPublishDefaults(
        videoCodec = supportedCodec,
        scalabilityMode = if (supportedCodec == "av1" || supportedCodec == "vp9") "L3T3_KEY" else null,
        simulcast = true,
        backupCodec = supportedBackup?.takeIf { it != supportedCodec }?.let { BackupVideoCodec(codec = it) },
    )
}
```

2.23.1 在 SVC 发布时会自动补备用编码；若传 `null`，其默认备用可能是 VP8，而本套件未启用 VP8。因此 AV1/VP9 发布者应明确提供已确认可用的 H.264 备用。这个 API 只设置编码偏好，不能指定某个 MediaCodec 实例，也不能强制硬编码。必须通过 RTC stats 中实际 codec、encoderImplementation、实际帧率和温度/功耗判断；字段因 WebRTC 版本不同可能缺失。SDK 的编码预设仍可能施加速率上限，省略参数不是物理无限速率。手机算力余量不能解决接收端不支持编码、120fps 硬编限制或热降频。

### 系统内录不是默认的双轨混音替代品

Android 10+ 内录需要 `AudioPlaybackCaptureConfiguration` 与有效 MediaProjection、`RECORD_AUDIO` 和允许被捕获的播放应用。常见捕获 usage 为 MEDIA/GAME/UNKNOWN；跨用户/profile、受 DRM 或 `FLAG_SECURE` 保护、禁止 AudioPlaybackCapture 的应用不可捕获。后台录音还要符合 microphone 前台服务及系统权限约束，不能靠 Root/Shizuku 注入脚本绕过这些 API 生命周期。

已核对的 Android 2.23.1 提供 `ScreenAudioCapturer.createFromScreenShareTrack(...)`、`LocalAudioTrack.setAudioBufferCallback(...)` 和 `releaseAudioResources()`，但其内建 capturer 是 **MixerAudioBufferCallback**：官方示例把系统音频混进麦克风同一条音轨。直接照抄该示例会破坏本套件需要的内录/人声独立处理，不能据此宣称已实现双轨隔离；其内部缓冲格式也继承已有 AudioDeviceModule 的声道配置，增加音频码率不会自动变成双声道。

因此本文的 MediaProjection 片段仅启用视频，**没有提供或宣称已经实现原生 Android 独立立体声内录发布模块**。完整原生 App 必须额外实现经验证的双输入音频管线：内录 AudioRecord 使用 48kHz 双声道 PCM、AEC/AGC/NS 关闭；麦克风单独采集/处理并发布为另一音轨。需要合适的自定义 AudioDeviceModule/PCM source 与独立处理路径，或分别配置的发布实例；不能把同一 AudioDeviceModule 下两条混合后的音轨当作两条原始输入。

内录轨应以 `Track.Source.SCREEN_SHARE_AUDIO` 标识，用 `AudioTrackPublishOptions(audioBitrate=256000, dtx=false, red=false, source=...)` 发布，语音轨标为 MICROPHONE 并使用独立 AEC/NS 配置。Android 2.23.1 的该发布选项没有 `forceStereo` 字段；立体声需在输入模块和 SDP/编码协商中验证。网页接收端已支持独立音轨，但服务端声明和网页能力不会自动补全手机 App 的这个音频模块。SDK mixer 若作为临时降级，必须明确告诉用户只有混合音轨且无法独立控制内录与语音。

## Shizuku 降级与 Binder 方案

### 可运行的 shell 降级

先启动 Shizuku（Root 或 Android 无线调试方式），按 Shizuku 应用的终端使用说明导出 `rish` 和配套 dex，放在可信 Termux 私有目录，并允许 Termux 使用 Shizuku。rish 的文件名、包名和加载方式随版本变化，不能只下载一个任意脚本冒充完整安装。Android 14+ 对可写 dex 有加载限制，应按当前官方导出提示调整 dex 权限。

以下假定导出的 rish 是 `$HOME/shizuku/rish`，且已按导出说明配置包名：

```sh
export RISH_APPLICATION_ID=com.termux
export RISH_PRESERVE_ENV=0
sh "$HOME/shizuku/rish" -c '/system/bin/id -u'
sh "$HOME/shizuku/rish" -c '/system/bin/wm size'
python -B "$HOME/android-control.py" --backend shell --width 1080 --height 2400 --shell-prefix "/system/bin/sh $HOME/shizuku/rish -c" --token-file "$HOME/.android-control/runtime.token"
```

该方式的 Python 仍在 Termux 普通 UID 下运行，只有 probe 和有限的 `input` 子命令经 `rish` 到 Shizuku shell。UID 检测必须为 `2000` 或 `0`，否则启动失败。`RISH_PRESERVE_ENV=0` 避免把 Termux 的 `LD_PRELOAD/PATH` 传到无权访问 Termux 私有库的 shell；rish 在 Termux 一侧加载导出的 dex，并不让 shell UID 直接运行 Termux Python。路径有空格时，`--shell-prefix` 内部的每个路径也要按 shell 规则单独引用。

同一个认证本机 HTTP、授权 session、序号、TTL 和看门狗仍然适用，协议仍然是完整 `snapshot`。区别是 shell 后端只接受一根手指，并在最后 `points:[]` 时把缓存的起点、终点和时长近似成 `input touchscreen tap` 或 `input touchscreen swipe`。时长截断至 1..1000ms，没有轨迹重现；快照期间并未真正按住屏幕。长按近似为同点 swipe，设备实际行为需验证。

- rish/JVM/Binder 启动和整段 swipe 执行会增加明显延迟，远不等价于 120Hz 连续注入。
- 不支持真正连续触控、多指、实时拖动反馈、压力、复杂曲线路径和多个显示器；多点包返回 422。shell 的 width/height 是**当前方向的逻辑屏幕像素**，rotation 必须为 0，不能配置 Root ABS 覆盖参数。
- 同时只启动一个 shell 手势；前一子进程未结束时，新的完成手势丢弃并返回 429，不积累执行队列。子进程退出码不能作为同步 HTTP 的成功承诺，200 仅表示已接收/启动；Shizuku 停止、授权丢失或 ROM input 失败均可能导致无动作。
- 看门狗、reset 和 revoke 会丢弃尚未执行的缓存手势；已经执行的有限时长 `input swipe` 不会被强杀，因为中途杀死可能阻止其 up。它不能被可靠撤销，不能给出 Root 模式的实时释放承诺。
- 线上协议故意不区分最后 up 与 cancel，均为 `[]`。因此 shell 降级收到远端 cancel 也可能完成缓存手势；需要取消时由可信本机应用调用 `/reset` 或 `/revoke`，但不能撤回已启动的命令。这是降级模式的真实限制，不适用于需要精确 cancel 的控制。

HTTP 不接受命令字符串，`input` 的参数仅由已校验的坐标与有限时长生成；`--shell-prefix` 是设备所有者的可信启动配置，不能从远端包或未经认证配置中获取。标准库以参数数组调用进程，传给 rish 的命令用 `shlex.join` 引用，不把远端 JSON 当 shell 代码执行。shell 后端也是一个认证本地脚本桥，但不是低延迟触屏驱动。

### 需要连续注入时的原生 Binder 路径

非 Root 设备若要进一步尝试连续多点注入，需要开发并获用户授权的原生 Shizuku 应用：集成官方 `dev.rikka.shizuku:api`/provider，等待 Binder 接收，检查 `Shizuku.checkSelfPermission()`，按 SDK 的 `Shizuku.requestPermission(requestCode)` 与授权回调处理拒绝/撤销，通过 `Shizuku.bindUserService(...)` 的受控 AIDL 服务承接输入。不要把任意输入 Binder 接口导出给所有应用。

在获得 shell/Root 身份的 UserService 中，按目标 Android 版本通过隐藏 `android.os.ServiceManager.getService("input")` 获取服务 Binder、`android.hardware.input.IInputManager.Stub.asInterface(...)` 获取接口，再调用该版本的 `injectInputEvent(...)`。另一官方 Shizuku 机制是以 `ShizukuBinderWrapper` 包装 system service Binder；必须按目标系统隐藏接口签名实测，不能假定普通应用里的 `InputManager` 调用会自动获得 Shizuku 身份。AOSP 不同版本中输入接口所属类、注入签名和 target-UID 方法有所变化，还受 `INJECT_EVENTS`、SELinux、隐藏 API 限制和厂商策略约束。

原生服务必须构造正确的 `MotionEvent.PointerProperties`/`PointerCoords`、`SOURCE_TOUCHSCREEN`、稳定 pointer ID 和 downTime。由连续完整快照差分产生 `ACTION_DOWN`、`ACTION_POINTER_DOWN | (index << ACTION_POINTER_INDEX_SHIFT)`、`ACTION_MOVE`、`ACTION_POINTER_UP`、`ACTION_UP`，撤销/失联发 `ACTION_CANCEL`，最后 recycle MotionEvent。还需实现与本文相同的鉴权、session/seq 检查和本地独立 250ms 看门狗。这是要针对 ROM 开发和测试的原生适配工程，**本文没有提供或声称已经实现该 Binder 多点后端**；不能用一行虚构的 `Shizuku.injectTouch()` 代替。

## 验证与上线检查

不需要 Android 或 Root 的主机测试：

```sh
python3 -B nixos/modules/services/livekit-suite/test-android-control.py
# 若主机只有 Nix：
nix shell nixpkgs#python3 --command python3 -B nixos/modules/services/livekit-suite/test-android-control.py
```

测试使用假的事件写入器验证载荷、序号/session 绑定、TTL、reset/revoke、完整状态的缺失触点释放、tracking 生命周期、旋转/ABS 范围、周期快照、看门狗、HTTP POST/token/Origin/长度约束、私有运行期 token 文件和 shell 参数生成。没有用虚拟成功结果冒充真机注入验证。

上线必须用真实设备验证以下项目：

1. uinput 设备创建、Android InputReader 识别、四角/中心命中、旋转、主显示器绑定及缩放；两指按下、移动、单指抬起和全部释放。
2. 人为丢掉最后 []、暂停控制端、控制者离房、网络重连、本地撤权、授权超时、daemon `SIGTERM` 与进程被杀后的真实释放行为。
3. 非授权房间参与者、同 identity 新 SID、旧 session、乱序/重复 seq、错误 token 和直接浏览器 HTTP 均不能注入。
4. Android 采集授权拒绝、系统停止分享、锁屏、前台服务限制、ROM SELinux 和 Shizuku 授权丢失都可见地停止控制。
5. 实测分辨率/帧率/编码器协商、热降频、网络丢包与触控到画面反馈延迟；不把 120Hz 配置或 codec 名称当性能与硬件保证。

参考已核对的版本源码：[LiveKit Android v2.23.1 LocalParticipant](https://github.com/livekit/client-sdk-android/blob/v2.23.1/livekit-android-sdk/src/main/java/io/livekit/android/room/participant/LocalParticipant.kt)、[RoomEvent](https://github.com/livekit/client-sdk-android/blob/v2.23.1/livekit-android-sdk/src/main/java/io/livekit/android/events/RoomEvent.kt)、[ScreenCaptureParams](https://github.com/livekit/client-sdk-android/blob/v2.23.1/livekit-android-sdk/src/main/java/io/livekit/android/room/track/screencapture/ScreenCaptureParams.kt)、[SDK manifest](https://github.com/livekit/client-sdk-android/blob/v2.23.1/livekit-android-sdk/src/main/AndroidManifest.xml)、[Android MediaProjection](https://developer.android.com/media/grow/media-projection)、[Shizuku API](https://github.com/RikkaApps/Shizuku-API)、[rish 官方说明](https://github.com/RikkaApps/Shizuku-API/blob/master/rish/README.md)。
