# img-deploy

## Purpose

Stream a NixOS-built raw image directly to a remote disk over SSH without storing a full image locally.

## Quick usage

Make the scripts executable:

```sh
chmod +x scripts/_img_deploy_common.sh scripts/img-deploy.sh
```

Example (adjust args):

```sh
./scripts/img-deploy.sh \
  --target .#nixosConfigurations.tyo0.config.system.build.sdImage \
  --host tyo0 --user root --port 22 --device /dev/sda --compression zstd
```

## Security

- This will overwrite the specified device on the remote host. Double-check the `--device` value.
- Use `ssh-copy-id` once to avoid password prompts on repeated runs.

## deploy-reinstall-dd

Purpose:

- Reinstall a non-NixOS machine into Alpine Live first, then stream a NixOS image directly to target disk with `dd`.
- Image is prepared locally (build/download), so target host can have no internet.

Key defaults:

- `--device /dev/vda`
- `--port 22` (current SSH connection port)
- `--reinstall-ssh-port <same as --port>` (port written into `reinstall.sh` stage for Alpine login)
- `--zstd-level 1`

Example (standard):

```sh
make deploy-reinstall-dd \
  host=can0 target-host=root@1.2.3.4 device=/dev/vda port=22
```

Example (NAT/port mapping):

```sh
make deploy-reinstall-dd \
  host=can0 target-host=root@1.2.3.4 device=/dev/vda \
  port=22 reinstall_ssh_port=10022
```

Example (`dd-only`, already in Alpine):

```sh
make deploy-reinstall-dd \
  host=can0 target-host=root@1.2.3.4 device=/dev/vda dd_only=on
```
