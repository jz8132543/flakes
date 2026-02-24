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
