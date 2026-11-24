# arx8 本地 AI

## 当前架构

- Strata 使用锁定 NUR 的 `pkgs.nur.repos.xddxdd.strata`，本次求值版本为 `strata-runtime-0.2.13.1`；使用该包配套引擎，不混用 Nixpkgs engine。
- 模型与运行配置位于 `/mnt/games/AI/strata`，不把权重写入 Nix store。配置目录为 `xdg-data/strata`，前台入口为上游生成的 `run-iq3_xxs.sh`。
- 模型 ID 为 `qwen3.8-flash-next-iq3_xxs`，8192 context、单并发、视觉关闭、`lowRam=mmap`。MTP 与缓存保留上游生成值。
- Strata API 监听 `127.0.0.1:11437`；llama-swap 监听 `127.0.0.1:8080`，目前仅登记 `llama-cpp`。
- Open WebUI 监听 `127.0.0.1:8081`，Traefik 提供 `https://open-webui.dora.im`。认证密钥仍由 SOPS 模板注入。
- 当前 WebUI 直接聚合两个 API，而非由 llama-swap 统一管理 Strata。这是现有实现的边界，不代表已满足计划中的显存互斥。

## 模型不显示的原因与修复

2026-11-23 检查确认 Strata 的 `/v1/models` 已返回模型，状态为 `loaded`。Open WebUI 数据库的 `openai.api_base_urls` 却仍只有 `http://127.0.0.1:8080/v1`。

Open WebUI 0.13.3 的 `OPENAI_API_BASE_URLS` 与 `OPENAI_API_KEYS` 使用分号分隔，不是逗号；环境变量仅为默认值，已经持久化的连接优先。只改环境变量或重启服务不能消除旧连接设置。

`nixos/modules/services/ai-local/llama-suite/llama-cpp.nix` 修正分隔符，并在现有服务的启动前仅同步以下四项：

- `openai.enable`
- `openai.api_base_urls`
- `openai.api_keys`，本地无认证后端的占位值，不是真实上游凭据
- `openai.api_configs`，清除旧连接索引的禁用、前缀或手工模型过滤

同步使用 SQLite 事务及幂等 upsert，不重建数据库、不修改账号或聊天、不关闭认证、不设置 `RESET_CONFIG_ON_START` 或全局 `ENABLE_PERSISTENT_CONFIG=False`。它针对当前锁定版本的 per-key `config` 表；未来数据库结构变更应重新验证，未知结构会报错而非猜测迁移。管理页面对这四项的修改会在下次服务启动时回到 Nix 声明值。

## 本次验证结果

2026-11-23 已执行 `nixos-rebuild switch --sudo --flake .#arx8` 并成功切换到 `/nix/store/yn1ind9n9180qq7sha8smpwgssslj5aa-nixos-system-arx8-26.11.20261113.d5cc683`。Open WebUI 启动前步骤成功，数据库连接列表包含两个地址，已有聊天仍存在。Strata 和 llama-swap 没有因本次修复重启。

使用锁定 Open WebUI 包的 `get_all_models`，在临时数据库中复用部署后的非敏感连接设置并请求真实两个后端，获得以下结果：

```json
[
  { "id": "qwen3.8-flash-next-iq3_xxs", "urlIdx": 0 },
  { "id": "llama-cpp", "urlIdx": 1 }
]
```

此验收不读取登录密码或运行服务认证密钥、不修改真实数据库、不关闭真实认证；它验证 WebUI 后端的模型聚合，不代替已登录浏览器选择器的视觉验收或聊天推理测试。部署后浏览器需刷新模型列表。

`nixfmt --check`、`git diff --check` 和 `nix build --no-update-lock-file --no-link .#checks.x86_64-linux.local-webui-config-test -L` 均通过，后者运行四项回归测试。没有运行全量 flake checks 或模型性能测试。

## 部署与日常检查

从仓库根目录部署：

```sh
nixos-rebuild switch --sudo --flake .#arx8
systemctl status strata open-webui llama-swap --no-pager
curl --noproxy '*' http://127.0.0.1:11437/v1/models
curl --noproxy '*' http://127.0.0.1:8080/v1/models
journalctl -u open-webui -u strata --since '-10 minutes' --no-pager
```

登录 Open WebUI 后刷新页面，在新聊天的模型选择器中选择完整的 `qwen3.8-flash-next-iq3_xxs`。旧聊天可能仍选择 `llama-cpp`，不会因连接修复自动切换模型。浏览器实际使用 `/api/models`，上游 `/v1/models` 成功不能单独证明浏览器列表已更新。

Strata 尚未声明 `wantedBy`，当前是手动启动的前台 systemd 服务。准备服务会生成运行文件，启动时可能下载缺失资源，不应为排查 WebUI 而反复运行。以下命令会实际准备或启动模型，须先检查空间和内存：

```sh
df -h /mnt/games
free -h
systemctl status strata-model-prepare --no-pager
sudo systemctl start strata
sudo systemctl stop strata
nvidia-smi
```

若需要重新准备，使用声明的 `strata-model-prepare.service`，不要手工替换引擎或删除已下载权重。包版本与计划参考的 v0.2.17 CLI 不同，不能直接照抄 `strata launch` 参数；先核对当前 `strata --help` 与服务参数。开机准备、自动启动、lazy 与 idle unload 的完整生命周期仍需另行完成验收。

## 资源与验收边界

- 本机 RTX 4060 Laptop 总显存约 8 GiB。修复前观察到 GPU 总占用 7287 MiB，Strata 服务约 6.9 GiB RSS；这些是运行快照，不是推理峰值或可用内存保证。
- mmap 专家模式会依赖操作系统文件缓存和磁盘回读。原 IQ3_XXS 的官方 RAM+VRAM 估算约 47 GB；48 GB 主机不能据此保证完全 RAM 驻留，swap 不等于物理内存。
- 本次修复不重新下载模型、不执行 quick tuning、不触发长 prompt 推理。未实测 tok/s、长会话稳定性、峰值内存或 NVMe 吞吐，不承诺这些指标。
- 当前生成运行配置没有 `lazy_load` 和 `idle_unload_s`，打开列表前模型已经加载。本次不把列表成功描述为“首次请求才加载”或“600 秒后自动卸载”验收通过。
- llama-swap 的 600 秒 TTL 仅作用于 `llama-cpp`，不控制独立 Strata。两个大型模型并发加载的安全互斥尚未实现，不能同时加载两者。
- `tests/test-open-webui-local-config.py` 验证部署生成的同步代码、分号地址、无关设置及聊天保留、重复执行幂等、新安装跳过、未知数据库结构失败；不使用真实凭据或模型权重。

## DuET

DuET 是独立 PyTorch 钢琴转谱流程，不是 GGUF/llama.cpp 聊天模型；MIDI 可直接转谱，音频先经 Transkun 转 MIDI，再输出 MusicXML/MIDI。视频仅能提取音轨。它不能作为本轮 Open WebUI 聊天模型登记，上传和结果下载适配器不在本次范围。Wayne42/DuET 权重采用 CC BY-NC 4.0，商业使用受限。
