# Corplink Nankai Access Handoff

This document is a technical handoff for another AI or engineer continuing the
Nankai VPN/access work on host `arx8`. It intentionally contains no passwords,
TOTP seeds/codes, cookies, private keys, complete API responses, or credential
file contents.

## Requested Outcome

- Make `https://i.nankai.edu.cn/` usable from the user's desktop.
- Keep the Corplink Feilian VPN client running continuously and start it on boot.
- Stop repeated school authentication/login events. Prefer preserving the
  existing authenticated client session and reconnecting the WireGuard transport
  without logging in again.
- Preserve a clear distinction between normal VPN disconnect (`type=101`) and
  terminal/API logout (`/api/logout`). Do not log out on ordinary shutdown.
- Avoid creating unnecessary authentication events. This means preventing
  duplicate/repeated login attempts, not deleting, concealing, or bypassing
  school-side audit records.
- Keep secrets out of Nix expressions, store paths, process arguments, logs, and
  this document. Credentials are already supplied through SOPS-backed systemd
  credentials.

## Current Runtime State (2026-11-27 03:49 +08)

- Active and boot-default NixOS generation:
  `/nix/store/2jh4p9822ii8wfp82qrhbby75y3r1qbl-nixos-system-arx8-26.11.20261121.2786a2a`.
- `corplink-rs.service` is `active`, `enabled`, wanted by `multi-user.target`,
  and configured with `Restart=no`. Its current `NRestarts` is `0`.
- Corplink SOCKS5 is listening only on `127.0.0.1:1080`.
- The current Corplink configuration uses split routing, disables automatic
  host route installation, disables VPN DNS, and runs the SOCKS5/netstack mode.
  Its exact config file must not be read or copied into reports.
- The installed Corplink package is `/nix/store/f0wa8c9ajdi0jzg9wa97x74iywnqbkba-corplink-rs-0.5.6`.
- The Corplink peer's marked outer route was observed through physical Wi-Fi
  `wlp4s0` using mark `0x80000`; Mihomo's active config excludes UID 997. Do not
  change the routing ownership of UID 998 or priorities 8980/8985/8990.
- **Mihomo is unhealthy and repeatedly failing startup.** At the last check it
  was `activating`/`start-pre`, with a recent `Result=exit-code`, `MainPID=0`, and 473 restarts (440
  generic policy-preparation failure log events were counted over the recent
  window). Treat this as an urgent unresolved regression. Do not claim that
  routing/Internet access is healthy just because Corplink is connected.
- A recent Mihomo retry loop coincided with missing 8980/8985/8990 rules and an
  unavailable table 2022. Re-check before changing anything. Never flush routes
  or rules; preserve Mihomo's route ownership and restore its service through a
  correct declarative fix.
- No temporary `corplink_reconnect_test` nft table should remain. Verify before
  any new test.

## Code Layout and Configuration

- `nixos/modules/desktop/corplink-rs.nix`
  - Enables the unit only on `arx8`.
  - Has `wantedBy = [ "multi-user.target" ]` for boot startup.
  - Runs as dedicated UID 997, uses persistent state directory mode 0700, loads
    username/password using systemd credentials, and retains `Restart=no` to
    prevent a process failure from causing a login storm.
  - Keep this policy unless a concrete regression requires a narrowly tested
    change. Do not set `Restart=always` or `on-failure` as a substitute for the
    client's reconnect supervisor.
- `pkgs/corplink-rs/default.nix`
  - Packages pinned corplink-rs 0.5.6 source and the bundled wireguard-go/libwg.
  - Applies `pkgs/corplink-rs/reconnect-verified.patch` to the Rust source.
  - Applies `pkgs/corplink-rs/patches/wireguard-go/0001-cleanup-netstack-listener.patch`
    to the pinned Go source and runs `go test ./libwg`.
- `nixos/modules/services/sub.nix`
  - Mihomo TUN excludes UID 997 so Corplink's outer transport can bypass Mihomo.
  - Preserve this and the existing routing ownership constraints.
- `nixos/modules/desktop/mihomo.nix` and
  `nixos/modules/desktop/mihomo-runtime-policy.py`
  - Prepare runtime policy/config for Mihomo. Recent changes in this area have
    repeatedly failed the actual system service, even where synthetic tests
    passed. The exact current configuration is secret-bearing; never print it.
- `tests/test-mihomo-runtime-policy.py`
  - Existing tests include private-output permissions, immutable credential
    source, redacted YAML errors, and block/flow YAML edge cases. Running it can
    create `__pycache__`; prevent bytecode with `PYTHONDONTWRITEBYTECODE=1`, or
    remove only generated `.pyc` files afterward. Do not stage caches.

## Reconnect Patch Behavior

The current Rust patch makes these changes to the pinned upstream client:

- HTTP 401/403 are treated as explicit auth rejection; generic HTTP 5xx should
  not reset the session state.
- A VPN API application code 101 resets client login state; ordinary transport
  errors should not.
- Removes or redacts logs that exposed QR auth material, TOTP seed/code, raw API
  response structures, and complete VPN route lists. Never read old journal
  entries containing those values; query only filtered event names/counts.
- Adds 60-second VPN status reporting and a separately owned persistent
  WireGuard watchdog. Keepalive transport errors are nonfatal; handshake timeout
  triggers WG transport teardown/recreation using the same `Client` instance.
- Reconnect backoff bases are 5/15/30/60 seconds, capped, with jitter.
- Allows at most one automatic delayed session reauthentication; further explicit
  invalidation fails closed for manual recovery instead of looping credentials.
- Initial zero-handshake state gets a finite timeout; a valid nonzero handshake
  is monitored for staleness.
- Graceful shutdown sends VPN disconnect type 101 but not terminal `/api/logout`.

The Go patch serializes C ABI lifecycle calls, closes the SOCKS listener and
accepted connections before tearing down the WG device, and supports rebinding
the same SOCKS port after reconnect. It has tests for same-port restart,
accepted-connection closure, and failed-bind behavior.

## Work Already Performed and Findings

1. Inspected the pinned upstream corplink-rs lifecycle. The original code had
   keepalive disabled, returned from keepalive on its first error, exited the
   process on handshake timeout, and performed terminal logout on graceful exit.
2. Inspected state handling. Transport errors should retain `State::Login`; an
   explicit invalid-session response may reset it. The original generic
   non-2xx handling was too broad and could turn transient 5xx into a login.
3. Inspected wireguard-go. `stopWg()` originally did not own/close the SOCKS5
   listener and accepted connections, making netstack restart on the same port
   unsafe. Added a pinned-source patch plus offline Go lifecycle tests.
4. Added the Rust reconnect/logging patch and package wiring. Built the package:
   Go lifecycle tests passed, and 46 Rust tests passed at that time. Built and
   deployed a Corplink-only/current-source system closure more than once.
5. A real one-time Corplink run successfully logged in, established a WG
   handshake, served SOCKS on loopback, and sent keepalives. During that run an
   upstream log exposed TOTP seed/code; the service was stopped immediately,
   logging was redacted, the package rebuilt, and the sanitized version was
   deployed. Do not reproduce or quote the old journal output.
6. Initially, HTTP DIRECT routing to the Nankai site was requested. Mihomo rules
   currently include broad domestic `GEOIP,cn,DIRECT` after earlier rules and
   before `MATCH,PROXY`; no specific `i.nankai.edu.cn` rule was found. A direct
   route is not the same as the school VPN. Determine whether the site requires
   the campus VPN, campus DNS, or only domestic direct access before choosing
   routing. Do not assume `GEOIP,cn,DIRECT` works for this host.
7. Tested a narrowly scoped nft OUTPUT drop for a Corplink UID/peer endpoint,
   with an automatic timeout. The rule counter stayed at zero and the handshake
   refreshed, so this did **not** constitute a valid outage test. The temporary
   table was deleted. Do not call reconnect verified on that basis.
8. Corplink has since been explicitly changed to boot-start and its runtime
   stability was observed: current process has remained active with zero
   systemd restarts, repeated successful keepalives, and multiple watchdog
   reconnect events followed by `WireGuard transport restored` in the recent
   journal summary. This is evidence that the internal supervisor has exercised
   recovery, but does not prove the last outage was an externally induced,
   controlled network failure.
9. `nixos-rebuild switch` once caused Mihomo's runtime policy preparation to
   fail and systemd `Restart=always` to retry continuously. The unit uses one
   `LoadCredential=config.yaml:/etc/mihomo/config.yaml`, `ProtectHome=true`, and
   its ExecStartPre now points to a Nix-store Python script. One probe of the
   exact store-backed script and credential exited successfully, while the
   installed service later returned to repeated failure. Synthetic unit tests
   have passed but are not sufficient to claim Mihomo is fixed. Latest check:
   13 tests passed, but Mihomo service still shows hundreds of recent generic
   failures. Investigate runtime environment, exact unit/script/policy path,
   and run the same preparation path with correct `$CREDENTIALS_DIRECTORY`
   expansion and a private `/run/mihomo` before restarting. Do not log YAML or
   exception messages that can contain secret lines.
10. During tests, Python `.pyc` caches were accidentally staged under
    `nixos/modules/desktop/__pycache__` and `tests/__pycache__`. Both were
    removed. No `__pycache__` or `.pyc` should remain in the worktree or index.

## Current Access Question: `https://i.nankai.edu.cn/`

The user's first requirement is to access this URL. No successful browser-level
test has yet established the correct path. The current client exposes a
loopback-only SOCKS5 listener at `127.0.0.1:1080`; Mihomo is a separate proxy
path and currently unhealthy. Use these safe diagnostics before modifying rules:

1. Check current DNS resolution for `i.nankai.edu.cn` using the active resolver;
   do not dump private resolver config.
2. Determine whether the address is public or campus/private and whether the
   school explicitly requires VPN. Compare route selection for the destination
   under normal user UID and Corplink UID 997 without changing routes.
3. Test the site through the Corplink SOCKS endpoint (for example using a
   browser proxy setting or a one-shot HTTP client that does not follow or print
   auth redirects/cookies). Do not save cookies/tokens or log response bodies.
4. If only Mihomo DIRECT is needed, add a narrow `DOMAIN,i.nankai.edu.cn,DIRECT`
   or appropriate domain-suffix rule before `MATCH,PROXY`, but first determine
   whether that bypasses a required campus VPN. Keep school VPN internal
   traffic routed through Corplink when required.
5. Do not put school credentials into browser proxy settings or shell history.
   SOCKS auth is disabled by this client; listener is loopback-only.

## Logging / Audit Boundary

The user said they want to minimize login traces because the school reported
repeated logins. The legitimate engineering objective is to eliminate redundant
authentication by preserving a valid session and reconnecting transport. Do not
delete local journal entries, alter timestamps, spoof identity, evade MFA, hide
activity, or advise bypassing the school's audit systems. Redact credentials and
tokens from local logs, while leaving normal, non-sensitive operational events.

## Safe Next Steps for the Next AI

1. **Do not start by switching or editing broadly.** Check `git status` and the
   index carefully; there are many unrelated staged/unstaged changes. Preserve
   them. Use current generation `2jh4p982...` as the runtime baseline.
2. Resolve Mihomo's persistent restart failures first, because adding website
   DIRECT rules while its policy runtime is failing will not provide usable
   access and can destabilize routing. Keep Corplink running during Mihomo work.
3. Reproduce the exact Mihomo ExecStartPre under the actual systemd sandbox:
   one credential, service user `mihomo`, RuntimeDirectory mode 0700, store
   script, policy JSON. Ensure `$CREDENTIALS_DIRECTORY` is expanded by a shell;
   passing a literal string is not equivalent. Capture only exit status, fixed
   validation category, and output file mode. Never print YAML.
4. Run `PYTHONDONTWRITEBYTECODE=1 <locked-python-with-pyyaml> tests/test-mihomo-runtime-policy.py`.
   The current 13 tests have passed, but continue to add a regression test for
   the exact active failing configuration shape without embedding its contents.
5. Check `systemctl show mihomo.service` and filtered event names before restart.
   If needed, stop only the Mihomo retry loop while debugging; do not flush
   routes, disable NetworkManager, or modify priorities 8980/8985/8990.
6. Once Mihomo is stable, test access to `i.nankai.edu.cn` with privacy-safe
   DNS/route/HTTP status checks and determine direct-vs-VPN requirement.
7. A real controlled reconnect test needs an isolated failure injection that is
   proven to match the active Corplink peer socket (non-zero counter) and has a
   guaranteed cleanup timer. The earlier OUTPUT rule missed the socket. Do not
   disable Wi-Fi or broad networking. Before injecting, record active peer,
   route mark, firewall owner, and recovery path; after the test, verify cleanup,
   routes, Mihomo, Corplink, handshake, and NRestarts.
8. Keep `Restart=no`, Corplink boot-enabled, and the service running at the end.
   Do not claim “no login traces”; report only verified authentication/reconnect
   counts and system status.

## Test Results / Boundaries

- Corplink package: Go lifecycle tests passed and Rust 46-test suite passed for
  the deployed package build.
- Corplink runtime: automatic login and initial WG handshake observed; keepalive
  successful; four watchdog reconnect events and four `WireGuard transport
restored` events were counted in the recent safe log summary; systemd
  `NRestarts=0`.
- Controlled network outage injection: **not verified**. Previous scoped nft
  test did not match traffic (counter zero), was removed, and must not be called
  a successful test.
- Mihomo policy tests: 13/13 passed in the latest targeted run, but current
  Mihomo service restart failures remain unresolved; inspect current state before
  relying on those tests.
- School portal browser acceptance: not yet proven.
- This handoff contains no secret values. Do not add any.
