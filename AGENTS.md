# Agent Instructions

This is a multi-host NixOS flake with Home Manager, local packages, and infrastructure automation. Preserve reproducibility and prefer small declarative changes in the existing architecture.

These instructions adapt public NixOS examples and recurring requirements from this project's conversations. Historical requests are context, not standing permission to deploy, commit, or change permissions. Current user instructions and current source files take precedence over stale examples or memory.

## Repository Map

- `flake.nix`, `flake/`: inputs and flake-parts outputs. `flake/hosts.nix` owns the active `hostDefinitions`; do not assume every host directory is an exported configuration.
- `nixos/hosts/`: host-specific hardware and feature selection. `nixos/modules/`: reusable system configuration and services.
- `home-manager/hosts/`, `home-manager/modules/`: user configuration, applications, and user services; keep the system/user boundary intact.
- `lib/`: module discovery, overlays, shared data, and helpers. `pkgs/`: local packages; check `pkgs/default.nix` and `flake/packages.nix` before adding exports.
- `tests/`, `flake/checks.nix`: regression tests and check wiring. `flake/treefmt.nix`: authoritative formatter/linter configuration.
- `devshell/`, `nixago/`, `Makefile`, `scripts/`, `terraform/`: development and operational automation; inspect commands before running them.
- `docs/`: subsystem architecture and operational caveats. `archive/`: preserved configurations, some still imported by active modules.

## File Organization and Code Quality

- Group software-specific configuration and supporting files in a clearly named directory for that application or service, within the appropriate `nixos/modules/`, `home-manager/modules/`, or `pkgs/` subtree. Do not mix unrelated applications' Nix files, scripts, patches, and assets in a flat shared directory.
- Keep a software integration's Nix modules at its directory root; use local `scripts/`, `patches/`, or `assets/` subdirectories when it has those supporting files. The goal is grouping by software, not moving every application's scripts into one global script pile. Keep system and Home Manager parts in their respective trees.
- Shared category directories should remain easy to browse: application/service directories plus genuinely shared policy modules. Do not add application-specific helpers next to many unrelated software modules. Existing small single-file integrations need no empty scaffolding; group them when they grow or are explicitly reorganized.
- Use descriptive file names and split by responsibility only when it improves readability. Do not create an unnecessary `default.nix` just to make a directory look conventional; follow the loaders described below.
- When moving files within the requested scope, update imports, relative paths, package references, systemd commands, and tests together. Check the module discovery result. Do not perform a repository-wide cleanup or move unrelated user work without a request.
- Favor focused modules, clear names, typed options, and minimal duplication. Extract shared logic only when it is genuinely reusable; avoid giant catch-all modules, speculative abstraction layers, and one-line helper files that make navigation harder.
- Make scripts idempotent where appropriate, declare dependencies, propagate meaningful failures, and handle temporary files, child processes, and locks correctly. Avoid unbounded retries, busy loops, and unnecessary background work; test relevant failure and cleanup paths, not just the happy path.

Example layout for an integration with multiple files, adapted to the owning module's actual namespace and loader:

```text
nixos/modules/desktop/example-app/
  options.nix
  service.nix
  scripts/
    helper.sh
  assets/
    icon.svg
```

## Repository Workflow

- Read the affected files and their callers before editing. Check Git status and preserve existing staged, unstaged, and untracked work. Do not reset, stash, delete, or broadly stage someone else's changes.
- Prefer official Nixpkgs derivations and upstream modules, settings, IPC, and lifecycle management. If an adjustment is necessary, reuse the existing derivation with a narrow override instead of rewriting its packaging.
- Avoid custom wrappers, polling daemons, duplicate systemd services, and reimplemented upstream features. Explain why upstream cannot meet the requirement before adding a custom implementation.
- Avoid upstream source patches as far as possible; prefer supported configuration, IPC, and upstream implementations. Do not use `sed`/`substituteInPlace` or another source-rewriting mechanism to disguise a patch or bypass approval.
- Before introducing, enabling, or expanding a source patch, explain why the feature cannot work without it, what would change, the maintenance/update risks, and any non-patch fallback. Ask the user whether to implement the patched feature or skip/defer it, and wait for an explicit decision before making those changes. A feature request alone is not patch approval. Leave existing approved patches intact when they are outside the task's scope.
- An explicitly approved source patch must still be minimal, tied to the pinned source, justified, and covered by a relevant regression test.
- Do not force an unsupported feature with unsafe hacks. State the limitation and keep a working fallback; login-dependent desktop applications need not be forced into pre-login system services.
- Keep service-specific firewall rules, startup logic, and shortcuts with the owning module. Shared network policy belongs in its existing shared module, not an unrelated application's file.
- Generate application settings and desktop shortcuts through NixOS/Home Manager options, not manually maintained files in `~/.local/share/` or ad-hoc changes to generated `/etc` files. Respect upstream-owned mutable state and distinguish initial defaults from settings that actually override existing state.
- Keep large images, downloaded sources, binaries, and build artifacts out of Git. Prefer pinned fetchers or reproducible derivations producing resources in the Nix store; retain only source code and small necessary assets.
- Finish the complete requested feature set before building or testing, except when an early focused test is needed to resolve a dangerous uncertainty. Follow the risk-based workflow below; avoid repeated checks, evaluations, builds, and switches after individual edits.
- Diagnose root causes with evidence. Do not replace a failing path with an unrelated workaround or claim a suspected cause is proven.

## Nix Conventions

- Follow nearby code and the configured `nixfmt` style, normally two-space indentation. Do not reformat unrelated files or switch the repository to Alejandra just because it is installed.
- Verify packages, options, flags, and APIs against the inputs pinned in `flake.lock`; current upstream documentation may describe a different version. Use the repository's locked inputs for tools rather than the global `nixpkgs` flake registry.
- Keep evaluation pure. Avoid new `<nixpkgs>` imports, machine-specific absolute source paths, unpinned fetches, and `--impure` workarounds that hide a configuration error. Do not update inputs or `flake.lock` as incidental troubleshooting; dependency changes must be scoped and intentional.
- Reuse the existing option namespace; the file's directory does not necessarily match `services.*`. Declare configurable behavior with typed `lib.mkOption`/`lib.mkEnableOption` and guard definitions with `lib.mkIf`.
- Use `lib.mkDefault` for overridable defaults and reserve `lib.mkForce` for deliberate overrides with a reason. Use module merging semantics, not shallow `//`, when combining option definitions.
- Do not make `imports` depend on the final `config`; keep the module graph independent and conditionalize definitions with `mkIf`. Reuse established `specialArgs` rather than introducing recursive dependencies through `self`.
- Understand the loaders before adding `default.nix`: `flake/hosts.nix` exposes `nixosModules` from `lib/rake.nix`, which uses Haumea to map `.nix` files and directories into an attribute tree. The `rake` transformer recursively adds an `.all` list to every directory, flattening child `.all` lists (or wrapping leaf modules in lists); it asserts that no loaded directory already defines an `all` attribute. Thus `nixosModules.services.ai.all` is an import list containing all discovered modules below that directory. It is suitable for importing a whole module group, not for selecting individual services from that group. Import a module file or narrower subtree when only selected services should be active.
- Do not claim that `lib/rake.nix` itself excludes directories containing `default.nix`: its transformer has no such special case. Haumea loads `default.nix` as the `default` entry; it may be included in the recursive `.all` collection alongside other entries. By contrast, `lib/rake-leaves.nix` explicitly collapses a directory with a `default` entry to that module and asserts that `default` is the only entry. Because loader behavior differs and a `default.nix` can obscure grouping and selection, prefer descriptive Nix filenames and avoid `default.nix` in module directories unless the specific loader/caller requires it. Do not remove package entry points or existing imports blindly.
- Prefer controlling whether a service is present by explicitly importing its module, rather than adding an `enable` option that duplicates module selection or making services enabled by default behind such an option. Keep options for genuine runtime/configuration parameters, not as a second service-selection mechanism. When a group `.all` is imported, every module in that group is imported; structure groups so that this matches intended activation, and use explicit module imports for optional services.
- Keep implementation logic separate from service settings. For a simple single-file module, define local configuration values near the top in a `let ... in` expression; when settings are substantial or configurable through NixOS options, keep them in a focused `settings.nix` (or the existing application-specific settings module) and keep service implementation in its own module. Avoid moving unrelated configuration into host files.
- Avoid editing `nixos/hosts/<hostname>/default.nix` for reusable configuration or when an existing shared import point/module can own it. Host files should primarily select hardware and host-specific modules. If behavior genuinely needs to differ by hostname, prefer deriving it from `config.networking.hostName` in the relevant shared module rather than duplicating host configuration, provided that does not obscure service selection or create unwanted host coupling.
- Use `config.ports` and its shared registry in `nixos/modules/base/module/misc/ports.nix` for service ports. Check collisions, listeners, reverse proxies, and firewall exposure together.
- For embedded shell code, quote arguments with `lib.escapeShellArg`, declare runtime dependencies, and escape shell interpolation as `''${...}` inside Nix indented strings.

## Secrets and State

- Never put plaintext credentials, tokens, or private keys in Nix expressions, the Nix store, logs, or documentation. Use existing sops-nix helpers, `sops.secrets`, and runtime secret paths; use `sops.placeholder` in restrictive templates and consume their `.path` through `environmentFiles` or service arguments.
- All sensitive information must be encrypted with SOPS. The user edits SOPS files; agents must not add or change encrypted secret values. When a change needs a secret, provide the exact SOPS key/path structure to add or modify and safe instructions for generating its value, without asking the user to disclose the plaintext.
- For Terraform domain or DNS changes, make the required Terraform configuration edits but leave deployment to the user because deployment may require a password. Do not run Terraform apply or deployment commands unless separately authorized in the current task.
- For programs with a login page, use username `i` and the password provided at runtime from the SOPS-encrypted `password` secret. If a program accepts only a password and no username, use that same secret password. Never hardcode or expose the password in configuration, tests, logs, or documentation; if the required secret structure is missing, tell the user its SOPS path and how to generate a suitable value.
- Do not read or decrypt credentials just to inspect configuration. Keep secret ownership, permissions, and service ordering explicit; do not disable authentication, TLS verification, or broad security controls to make a test pass.
- Do not casually change `system.stateVersion`, `home.stateVersion`, disk layouts, hardware IDs, persistence paths, or container/VM installation parameters. In particular, version/language changes can trigger a destructive guest reinstall; consult `docs/winpodx-architecture.md` for that subsystem.
- Preserve policy-routing ownership and boot dependencies. Do not flush routes/firewalls or disable NetworkManager-wait-online as a shortcut. DN42 owns priorities 80/81/90, overlay isolation owns 8990, and Mihomo's 8980/8985 rules must remain intact; consult `docs/dn42-architecture.md` and current modules.
- Edit generators rather than generated outputs: `pkgs/nvfetcher.toml` rather than `pkgs/_sources/*`, Nix configuration rather than generated `.sops.yaml`/`.pre-commit-config.yaml`, and the Terraform extraction template rather than `lib/data/data.json`.
- Do not blanket-delete `archive/` or `*.bak`: active GNOME wrappers explicitly import archived `.nix.bak` files. Keep `.direnv/`, result links, Terraform state/plan files, and image artifacts out of changes.

## Validation and Deployment

- For low-risk changes, such as ordinary application settings or appearance changes without security, connectivity, or state implications, finish all code first. When deployment is authorized in the current task, build and switch the affected system once, then test the actual features on the deployed system. Do not routinely run `nix flake check`, separate full evaluations, or a series of targeted check builds beforehand.
- An authorized `nixos-rebuild switch` already builds before activating; do not duplicate that build with a separate full-system build unless there is a concrete need. A failed build must not be followed by activation of an older or unverified result.
- For dangerous changes, test before deploying. Examples include bootloader/kernel changes, disks and filesystems, persistence or VM installation parameters, credentials and access controls, SSH/firewall/DNS/policy-routing changes that can cut off access, and destructive data/schema migrations. Use focused tests for the relevant risks and prepare a recovery path; do not turn this into an automatic full-flake check sequence. If the safety boundary is uncertain, resolve that uncertainty before switching.
- Assess risk by actual effects, including activation scripts and service restarts, not merely by the file name or size of the diff. Inspect what the full switch would activate; do not silently deploy unrelated pending work from a dirty worktree.
- After deployment, verify the requested user-visible behavior and relevant failure paths. Fix any failures and repeat only the necessary build/deploy/test cycle. Writing a regression test does not require running it repeatedly during implementation; low-risk tests can run after deployment, while safety-critical tests must pass beforehand.
- Documentation-only changes do not require system builds or deployment. If deployment is not authorized, finish the code without switching and report that boundary.

Run commands from the repository root. Choose the affected host and check, not a stale name from an old conversation or CI workflow. The following examples use the currently exported `arx8` configuration and are an optional toolbox, not a checklist to run for every task.

```sh
# Discover current check names without running their test bodies.
nix eval --no-update-lock-file --json '.#checks.x86_64-linux' --apply builtins.attrNames

# Evaluate the host's complete system derivation without activating it.
nix eval --no-update-lock-file --raw '.#nixosConfigurations.arx8.config.system.build.toplevel.drvPath'

# Broad evaluation only when a specific need is not covered by focused tests.
# Do not build the check outputs; this is not a routine pre-deployment step.
nix flake check --no-build --no-update-lock-file

# Example focused desktop check; choose checks appropriate to the change.
nix build --no-update-lock-file --no-link '.#checks.x86_64-linux.desktop-evaluation-test' -L

# Build a host closure only when needed; this does not switch the system.
nix build --no-update-lock-file --no-link '.#nixosConfigurations.arx8.config.system.build.toplevel' -L

# Format only selected files with the repository's formatter.
nix fmt --no-update-lock-file -- path/to/changed-file.nix
```

- Evaluation can fetch inputs, populate the store, and encounter import-from-derivation. `--no-build` skips check builds, not necessarily every evaluation-time build. Ordinary `nix flake check` includes host/package builds here and is not a lightweight default.
- Git-backed flakes omit new untracked source files. If a new import is missing, inspect Git inclusion first; do not compensate with broad `git add --all` or silently change the source boundary.
- Add or update the relevant regression test for behavior changes, and run it at the appropriate stage of the risk-based workflow above. Use existing `tests/` conventions and wire reusable checks into `flake/checks.nix`; do not merely add assertions that reproduce the implementation.
- Temporary test examples or fixtures may be created when useful, but remove them when no longer needed; retain tests only when they provide lasting regression coverage for the requested behavior.
- `nix develop`/direnv install hooks and generate configuration. The `flake-treefmt` pre-commit hook does not limit itself to staged filenames. Inspect and account for these side effects; preserve unrelated work.
- System activation (`nixos-rebuild switch/test/boot`), service restarts, remote deployment, disk tools, and Terraform operations require authorization in the current task; this workflow is not blanket permission to run them. `make build` uses a remote builder; Terraform wrappers can decrypt/rewrite state, and `terraform-pipe` applies infrastructure and commits/pushes.

## Delivery

- Distinguish static checks, Nix evaluation, package/system builds, deployment, and real runtime acceptance. A successful command, mapped window, generated shortcut, or service marked active does not prove the requested user-visible behavior works.
- Report affected hosts/modules, checks actually run, results, and remaining limitations. Do not invent successful tests or hide a fallback; when runtime acceptance is requested and authorized, verify the actual application behavior.
- For requested architecture documentation, use `docs/` and record design, implementation, encountered problems, fixes, and verification boundaries. Update existing relevant documentation when it changes; do not generate unrelated documents or commit/push without an explicit request.

## Public References

These are references, not instructions to adopt another repository's hosts, directory layout, or deployment workflow.

- [AGENTS.md format and client compatibility](https://agents.md/)
- [Kilo AGENTS.md loading behavior](https://kilo.ai/docs/customize/agents-md)
- [Reidond/nixos-draft NixOS agent instructions](https://github.com/Reidond/nixos-draft/blob/HEAD/AGENTS.md)
- [T-Py-T/nix-homelab repository guidelines](https://github.com/T-Py-T/nix-homelab/blob/HEAD/AGENTS.md)
- [Aleks-Tacconi/NixOSConfig agent instructions](https://github.com/Aleks-Tacconi/NixOSConfig/blob/HEAD/AGENTS.md)
- [NixOS module reference](https://wiki.nixos.org/wiki/NixOS_modules)
- [Nix flake check semantics](https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-flake-check)
