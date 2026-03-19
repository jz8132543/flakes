# ssh-race

`ssh-race` is a `ProxyCommand` helper for OpenSSH.

It races candidate hostnames in parallel and returns the first TCP connection that succeeds.
After selection, it prints the winning hostname to stderr as `ssh-race: selected <host>`.

## Usage

```sshconfig
Host *
  ProxyCommand ${pkgs."ssh-race"}/bin/ssh-race -domains et,mag,dora.im %n %p
```

## Behavior

- Bare hostnames like `nue0` expand to `nue0.et`, `nue0.mag`, `nue0.dora.im`, then `nue0`.
- Fully qualified names like `github.com` are passed through unchanged.
- The helper uses direct TCP connections only; SSH performs the real handshake once on the winning socket.
