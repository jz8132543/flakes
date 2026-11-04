# 小磁盘 Nix 部署、GC 保活机制与复现指南

## 1. 结论与当前状态

本文记录 2026-11-03 至 2026-11-04 的排查、实现、实验与取舍。最新选择是：**删除源码补丁，使用官方 Nix 2.35，分离 A=4 GiB、B=1 GiB、C=30 GiB，并接受仍可能发生 GC 冲突的残余风险。** 下面保留历史方案的解释，避免丢失先前实验依据。

| 方案                                          | 是否修改 Nix 源码  | 是否保持原 push 命令                               | 保护结束点                                                  | 当前状态                                              |
| --------------------------------------------- | ------------------ | -------------------------------------------------- | ----------------------------------------------------------- | ----------------------------------------------------- |
| 历史方案 A：接收 store 查询时登记临时 roots   | 是，一个很小的补丁 | 是，覆盖已测试的正常 `local`、`ssh`、`ssh-ng` 复制 | 接收 store 会话释放临时 roots                               | 实验已验证，但补丁和自定义包已从工作树删除            |
| B：binary cache + 原生 `--realise --add-root` | 否                 | 否，需要改成目标机拉取并交接 root                  | 拉取后由 staging root 保护，profile 接手后删除 staging root | 官方 Nix 的离线核心实验已通过，SSH 运维流程未生产部署 |
| 当前：分离 A/B/C 阈值                         | 否                 | 是                                                 | 不额外延长 root 生命周期                                    | 降低 push 中途 GC 的概率，不保证彻底消除原问题        |

**原生 NixOS 配置不能在原 push 流程完全不变时，补上当前版本缺少的完整闭包保活调用。** 不修改任何 Nix 源码，可以改变流程，使用原生 substitution 和 GC-root 接口完成本次已验证的拉取与顺序交接。这是方案 B，不是简单调整 GC 水位；它也尚未证明任意外部 GC 并发下的严格部署事务，第 9.2 节说明该限制。

方案 B 不要求推送机有公网 IP，也不要求目标机访问公网 cache。已有 SSH 通路可以通过反向转发承载只监听 loopback 的 cache。完全互不连通的两台机器当然无法传输；这里要求的是原本能够 push 的 SSH 通路，而不是公网服务。

当前不再选择历史补丁方案 A；用户已明确接受阈值缓解不等于保活修复的取舍。方案 B 仍是独立的、未默认启用的替代流程。本文没有替用户执行系统切换、服务器 GC、密钥初始化、Git 提交或推送。

### 1.1 当前 A/B/C 环境变量

阈值 A/B/C 和历史方案名称 A/B 不是一回事。三个阈值在 `nixos/modules/base/nix.nix` 顶部定义为系统环境变量，单位全部为字节：

```nix
environment.variables = {
  NIX_GC_A = toString (4 * 1024 * 1024 * 1024);
  NIX_GC_B = toString (1024 * 1024 * 1024);
  NIX_GC_C = toString (30 * 1024 * 1024 * 1024);
};

nix.package = pkgs.nixVersions.nix_2_35;
nix.settings.min-free = lib.toInt config.environment.variables.NIX_GC_B;
nix.settings.max-free = lib.toInt config.environment.variables.NIX_GC_C;
```

| 阈值 | 字节值      | 用途                                                                                           |
| ---- | ----------- | ---------------------------------------------------------------------------------------------- |
| A    | 4294967296  | minimal 部署后低于 4 GiB 时删除全部旧 system generations；否则保留现有 configurationLimit 数量 |
| B    | 1073741824  | Nix 导入/构建期间低于 1 GiB 触发应急 auto-GC                                                   |
| C    | 32212254720 | 应急 GC 希望恢复到 30 GiB 可用空间；无可回收垃圾时仍会结束，不是必须满足的条件                 |

minimal 脚本现在独立读取 `NIX_GC_A`，不再把 A 绑定到 `min-free`。该脚本在两种分支后仍然调用 GC，因此 A 是激进删代的判定阈值，不是“只有低于 A 才 GC”的总开关。非 minimal 的 `fra0` 仍没有此部署后脚本。

环境变量供 shell 查看，但 Nix 设置和 activation 常量都在配置求值时生成。仅执行 `export NIX_GC_B=...` 不会重新配置已经运行的 daemon；应修改顶部定义并重新部署。使用 `config.environment.variables` 而不是 `builtins.getEnv`，也不要求 flake 用 `--impure` 才能读取这些阈值。

小于 30 GiB 的磁盘通常达不到 C，这不构成新的等待循环，但可能使每次应急 GC 更倾向回收全部不可达缓存。A 也不保证下一次推送前必然空出 4 GiB：受保护闭包、数据库、容器、swap 和其他非 store 数据都可能限制实际空闲空间。

如果推送开始时确实有 4 GiB 空闲，A-B 提供约 3 GiB 的新增预算，仍应扣除临时开销与其他写入。跌破 B 或遇到独立定时 GC 时，未打补丁的原复制失效窗口仍存在；当前策略没有增加事务 root、空间预留或新的全局锁。

### 1.2 文件布局

| 文件                                                                          | 职责                                                      |
| ----------------------------------------------------------------------------- | --------------------------------------------------------- |
| [`nixos/modules/base/nix.nix`](../nixos/modules/base/nix.nix)                 | 顶部环境变量、原版包选择以及 B/C 设置                     |
| `pkgs/nix-gc-safe/default.nix`、`nix-copy-gc.patch`                           | 已删除的历史路径，不再参与构建                            |
| [`tests/nix-copy-gc-test.py`](../tests/nix-copy-gc-test.py)                   | 旧版本失败、修复版本、混合版本和原生 cache 流程的黑盒测试 |
| [`nixos/modules/optimize/minimal.nix`](../nixos/modules/optimize/minimal.nix) | 用独立 A 判断删代分支，保留现有数量/天数政策              |
| [`flake.lock`](../flake.lock)                                                 | 固定实验使用的 nixpkgs 与其他输入                         |

本次不保留任何 GC 源码 patch 文件或自定义 Nix 包。已经运行的旧二进制不会因文件删除自动替换，需要重新部署后才使用原版包和新阈值；本次也没有强制清理仍被旧 generations 引用的构建产物。

## 2. 原始问题与约束

部分服务器只有约 10 GB 磁盘。用户观察到上传新系统时，磁盘越过阈值触发 GC，上传进度被回收，后续传输或重试又触发 GC，形成重复工作。

原始命令包括：

```bash
colmena apply --verbose --reboot --on tyo0,tyo1,hkg0,hkg5,sjc0,fra1
nixos-rebuild switch --sudo --flake .#cu --target-host cu.dn42
nixos-rebuild switch --sudo --flake .#fra0
```

第三条没有 `--target-host`，是在执行命令的本机应用 `fra0`，不能把三条命令都当成远端 push。

设计约束如下：

- 传输期间空间不足仍需要 GC，不能一律暂停回收。
- GC 不能反复销毁当前传输的必要进度。
- 不在整个传输期间持有全局 GC 锁，再等待 GC 释放空间。
- 不用“所有新路径保护一天”替代事务生命周期，否则一天内多次更新难以清理。
- 尽量复用 Nix 本身的能力，避免维护 Colmena 专用补丁或常驻清理管理器。
- 推送机可能没有公网；部署不能依赖一个公网可访问的发布服务。

### 2.1 三个回收入口，而不是只有一个 timer

最初排查时，共享配置的准确水位是以下值；现已替换为第 1.1 节的 B/C：

```nix
min-free = 3500 * 1024 * 1024;
max-free = 5000 * 1024 * 1024;
```

它们分别是 `3670016000`、`5242880000` 字节，约 `3.42 GiB`、`4.88 GiB`。原代码注释写的 `3.5 GiB / 5.0 GiB` 只是近似，不能当成准确单位换算。

实际需要考虑：

1. Nix 导入、构建过程中由 `min-free` 触发的 auto-GC。
2. `nix.gc.automatic` 对应的 systemd 定时清理。
3. minimal 的 activation 脚本：低空间时删除全部旧 system generations，否则保留配置数量，然后调用 `nix-collect-garbage`。

只关闭 timer 不会关闭另外两个入口。仅将 `min-free` 设为 0，也不会阻止 activation 中的全量 GC。

还发现一个模块优先级细节：base 的普通定义 `--delete-older-than 7d` 高于 minimal 的 `mkDefault "--delete-older-than 1d"`，不能看到 minimal 的字面值就声称实际 timer 是 1d。硬件配置也存在 `mkForce` 启用自动 GC 的定义。最新改动只分离阈值，没有改变保留天数、configurationLimit 或这些启用优先级。

## 3. GC roots、硬链接、数据库事务与锁

### 3.1 GC 判断的是可达性

一个 system generation 是 profile 的一个版本，指向一个 store path；系统闭包由该路径和所有递归 references 构成。GC 从持久 roots、临时 roots 和相关运行时 roots 出发寻找活路径。

因此，“目录已经出现在 `/nix/store`”“注册数据库中有该路径”“路径很新”，都不等于“这个路径有 root”。

Nix store optimisation 的硬链接去重是另一层机制。多个 store 文件可以共享同一个 inode；删除其中一个路径可能暂时不释放物理数据，但该逻辑 store path 仍可能被注销和删除。硬链接计数大于 1 不是系统闭包的保活白名单，也不能代替 GC roots。

### 3.2 Nix 已经有锁，但锁的范围不同

| 机制                       | 作用                                   | 不提供的保证                                                            |
| -------------------------- | -------------------------------------- | ----------------------------------------------------------------------- |
| Store 数据库事务           | 原子维护有效路径和 references 等元数据 | 不把多个 RPC、整个闭包上传和后续 activation 包成一个事务                |
| 全局 `gc.lock`             | 协调 GC 与 root 登记等关键步骤         | 不能在整个 push 中占用它，同时要求 GC 工作                              |
| 临时 roots                 | 保留某个 store 会话需要的路径          | 不会自动知道另一个后续 SSH 命令还要使用它们                             |
| 持久 root / system profile | 跨进程保留已完成闭包                   | 不会自动生成，也不能凭一个悬空顶层 symlink 保护尚未形成的 references 图 |
| 部署专用互斥锁             | 串行化遵守同一锁的一组 profile 切换    | 不自动协调 Colmena/nixos-rebuild，不是 GC 锁，GC 不应依赖它             |

不正确的锁设计是：push 持有某把锁并等待 GC；GC 又需要同一把锁才能运行。正确思路是保护路径，让 GC 正常回收保护集之外的垃圾。

### 3.3 `addTempRoot` 的原生同步

在本次使用的官方 Nix 2.35.3 中，`LocalStore::addTempRoot` 大致执行：

1. 创建并持有当前进程的临时 root 文件。
2. 非阻塞尝试获取共享 GC 锁。
3. 如果 GC 正在运行，改经 GC socket 发送路径并等待 ACK。
4. 把路径写入临时 root 文件，使之后启动的 GC 也能看到它。

这里没有在网络传输期间持续持有全局 GC 锁。临时 root 文件的存活通过文件锁判断；进程退出后，后续 GC 可以识别和清理陈旧文件，不需要固定的一天 TTL。

`read-only` store 的原生实现会跳过临时 root 锁文件创建。本次实验与部署讨论针对普通可写接收 store，不将只读模式当成另一种保活协议。

## 4. 发现了两个不同缺陷

### 4.1 已有依赖被跳过，却未被保活

用最小闭包描述问题：

```text
R -> B -> A

源 store：A、B、R 都有效，而且整个闭包有持久 root。
目标 store：已有 A，但 A 没有 root；B、R 还未导入。
目标还存在一个无关的垃圾 G。
```

Nix 2.34.9 的典型复制步骤是：

```text
查询目标的 valid paths -> 得到 A
跳过 A，只传 B、R
导入 B 时，临时 root 保护 B 自身
auto-GC 在 B 的有效注册完成之前运行
A 尚未通过 B 的 references 成为可达路径，也没有自己的 root
GC 删除 A，同时删除 G
注册 B 时发现 A 无效，复制失败
```

关键不是“新写入 B 完全没有临时 root”，而是**被复用的 A 没有进入当前复制的保护集**。单个导入路径的保护不能代替完整闭包保护。

官方 2.35.3 已修复下一节的同步问题，但它的普通复制仍存在这个已有依赖窗口。只升级版本不能把两个修复混为一谈。

实验验证的是这一失败窗口，不是证明 Nix 自己一定有无限重传循环。用户的循环表现还可能涉及外层重试、多个连接或重复操作；本次没有拿到能唯一归因全部生产现象的完整日志。

### 4.2 GC 已排队删除，后来才收到新临时 root

Nix 2.34.9 还有另一种竞态：GC 在遍历阶段判断路径是垃圾并排入删除列表，之后才收到新临时 root；如果删除阶段不重新检查，路径仍可能被删。

官方 Nix 2.35 的修复在删除前重新检查动态 `tempRoots`，并通过 `pending` 状态与 `addTempRoot` 同步。这是选择 2.35 的必要原因，不能只在 2.34 上加一个 root 调用就宣称所有同步窗口已经消失。

两个问题分别是：**有没有登记应该保留的路径**，以及**GC 是否正确处理新登记的路径**。

## 5. 历史方案 A：已删除的复制保活实现

本节仅记录曾经验证的代码和取舍，不是当前部署逻辑。用户已选择删除它，当前官方 Nix 不包含以下调用修改。

### 5.1 配置只选择包

旧的配置曾经选择：

```nix
package = pkgs.nix-gc-safe;
```

该选择已经替换为 `pkgs.nixVersions.nix_2_35`，对应自定义包和 patch 文件已删除。当时的补丁没有修改 Colmena；当前阈值方案也不修改 Colmena。

### 5.2 打包实现

已删除的 `pkgs/nix-gc-safe/default.nix` 原逻辑如下，仅作历史说明：

```nix
{ nixVersions }:
# 2.35 fixes GC/root synchronization; protect copy queries in the receiving store.
nixVersions.nix_2_35.overrideScope (
  _: prev: {
    nix-store = prev.nix-store.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./nix-copy-gc.patch ];
    });
  }
)
```

`pkgs/default.nix` 自动发现带 `default.nix` 的包子目录，因此不需要再手工注册一个 overlay 条目。

Nix 在 nixpkgs 中是模块化打包的。不能随意在最外层聚合包上加 `patches`，然后假设它一定重编译了 `libstore`。这里通过 `overrideScope` 替换真正构建 store 库的 `nix-store` 组件，保留已有 patches，并让其他组件引用修改后的组件。

该组件构建时的 source root 是 `src/libstore`，所以补丁路径是 `a/local-store.cc`，不是 `a/src/libstore/local-store.cc`。后者在这个 patch 阶段会指向错误位置。

### 5.3 唯一源码行为变化

修改后的函数为：

```cpp
StorePathSet LocalStore::queryValidPaths(const StorePathSet & paths, SubstituteFlag maybeSubstitute)
{
    StorePathSet res;
    for (auto & i : paths) {
        // Keep reused and not-yet-imported paths alive for this store session.
        addTempRoot(i);
        if (isValidPath(i))
            res.insert(i);
    }
    return res;
}
```

重要的是调用顺序和集合范围。

- 对全部请求路径调用 `addTempRoot`，不只处理 already-valid 路径或即将传输的 missing 路径。
- 在有效性判断之前登记 root，不采用“先查有效，再补 root”的窗口。
- 尚未导入的路径也可以登记其身份；它们导入后已有对应保护。
- 依然返回原来的有效路径集合，不改 wire protocol，不要求旧客户端发送新 RPC。
- 借用 store 会话原有的临时 root 生命周期，不制造永久 pending 系统列表。

因此正常复制完整查询 `[A, B, R]` 时，A 会被保留；B、R 的后续导入不会使本次进度回退，GC 仍可删除 G。

`ssh` 的 serve 接口、`ssh-ng` 的 daemon 接口以及本地复制最终使用的相应接收 `LocalStore` 查询，均在本次黑盒实验中验证了这一效果。旧 2.34.9 客户端连接新接收端的两种 SSH 协议也已验证。

### 5.4 必须知道的行为范围

此修改作用于 `queryValidPaths` 的所有调用，不是只识别“系统镜像”。长寿命 store 会话查询过的路径可能保留更久；没有按单个路径提前取消临时 root 的新机制。

保活依赖 store 会话仍存在。客户端若提前关掉查询连接，另起连接继续导入、复用已经失效的结果，或者第三方工具完全不查询完整闭包，本补丁不构成通用的跨连接事务协议。异常连接池策略、网络重连和任意第三方写 store 的方式没有在本次测试中穷举。

本地 rebuild 的构建期可受益于官方 2.35 的同步修复，但 `build --no-link` 结束到 profile 接手的空窗并没有因此成为事务。方案 A 的主张是已验证的复制会话内保活，不是整个 deployment 的原子性。

## 6. 其他考虑过、但没有默认采用的办法

| 办法                                   | 为什么不足或没有采用                                                                  |
| -------------------------------------- | ------------------------------------------------------------------------------------- |
| 传输期间关闭全部 GC                    | 空间紧张时不能释放其他垃圾，不符合要求                                                |
| 整个 push 持有全局 GC 锁               | push 再等待 GC 时形成锁依赖，违背并发回收需求                                         |
| 只暂停定时 GC                          | auto-GC 和 activation GC 仍存在                                                       |
| 只降低水位、增加检查间隔               | 降低触发概率，不补上保活调用                                                          |
| `keep-outputs`、`keep-derivations`     | 影响已有根之间的保留关系，不凭空创建新系统的 root                                     |
| 永久给所有新路径建 roots               | 失败或放弃的部署会积累，最终耗尽小磁盘                                                |
| 给未来系统先建一个悬空 symlink         | 尚未有效的顶层对象没有完整 references 图，不能由它推出已到达的依赖                    |
| 最近路径保护一天                       | 用户一天内可能部署多代；年龄不是进行中事务的生命周期                                  |
| 按 `registrationTime` 判断本机到达时间 | 至少部分复制接口会携带源端注册信息，不能通用于所有协议                                |
| 按 mtime 判断新旧                      | Nix store 时间规范化使其不适合表达传输时间；改成 ctime/首次观察时间也仍然只是时间策略 |
| 给 Colmena 加 root-holder              | 原生 serve 的 `lock=1` 可用，但需要持有连接、处理激活交接；不能覆盖原样使用的其他工具 |
| 换成 Lix 或盲选 Nix git 包             | 所检查版本并没有同时覆盖现有两种复制协议和交接窗口                                    |

曾尝试的 Colmena 专用实现已撤销，没有残留在 `devshell/default.nix` 中。历史方案 A 把小范围缺陷修复放在共同的 Nix 接收层，后来也按用户选择撤销。

方案 A 是源码补丁，不应把它包装成“完全没有补丁”。当前选择纯阈值策略是用户明确接受残余风险后的取舍，并没有把它宣传成同等的完整闭包保活修复。方案 B 则仍是改变部署步骤的另一条路径。

### 6.1 为什么没有直接换一个现成的更高版本

本次核查时，官方 2.35.3/2.35.4 已有动态 root 删除前重查，但普通 copy 仍先查询有效路径，再只复制 missing，因此不能只凭升级到 2.35 宣称方案 A 已经不需要补丁。

上游 PR #16113 的预登记复制集合工作在所检查的 master 中依赖新客户端和接收端的批量临时 root 能力；默认 `ssh` 的 `LegacySSHStore` 没有相同的实现，不能将它泛化到原 `nix-copy-closure` 流程。锁定的 `nixVersions.git` 当时为 `2.36pre20261020_f3f18483`，还早于修复旧 daemon root 调用回归的 `901c9b8`，所以没有盲目改成 git 版。

锁定的 Lix 输入为 `2.97.0-dev`；所检查的该输入和发布版 2.94/2.96 仍未同时提供这里需要的完整 copy 查询保活和删除前动态 root 重查。结论针对检查时的源码，不是断言以后所有版本都不会修复。更新时仍必须重新核查和运行实验。

## 7. 回归脚本如何复现所有关键行为

源码以 [`tests/nix-copy-gc-test.py`](../tests/nix-copy-gc-test.py) 为准，以下解释其全部主要组成。它是 standalone 测试，不因文件存在就自动成为 `nix flake check` 的一项。

### 7.1 参数与执行器

- `nix`：包含 `bin/nix` 等程序的包目录。
- 默认模式：运行 `local`、`ssh`、`ssh-ng` 三种复制，要求保活成功。
- `--expect-failure`：对未修复版本要求失败，并匹配 `is not valid`，不是把任意失败都当成复现成功。
- `--client`：指定旧客户端，接收端仍用第一个参数；只运行两种 SSH 协议。
- `--native-cache`：运行官方原生 cache 拉取与持久 root 交接实验，只使用本地独立 store。

失败预期与原生 cache 模式互斥；cache 模式不能和混合客户端组合。`command()` 收集 stdout/stderr，每个子命令有 60 秒上限。这个上限只属于测试，不是给生产 Nix 新加的超时策略。

### 7.2 构造闭包与隔离源端

`text_path()` 用 `builtins.toFile` 创建 A、B、R。`builtins.storePath` 携带 string context，使 B 真正 reference A、R reference B；不能只写一个普通无 context 的字符串，然后假定 Nix 已记录 references。

源端首先通过 `--realise --add-root --indirect` 为 R 建 root，排除“源端也被测试中的 GC 回收”这一干扰。每个协议使用独立目标，预先放入无 root 的 A 和无关垃圾 G。

所有 store 都使用 `local?root=<临时目录>`。数据库、store 文件和 GC 状态位于这个独立根目录中，测试不会对机器真正的默认 store 执行 GC。

### 7.3 不填满真实磁盘

脚本写入值为 `100` 的 fake-free 文件，只对该次复制/拉取子进程设置 `_NIX_TEST_FREE_SPACE_FILE`，再配置 `min-free=300`、`max-free=10000`、检查间隔 0。

这是已检查 Nix 版本的内部测试 hook，数值单位为字节。测试不需要真的写满几 GB。文件一直返回 100，也验证了复制成功不依赖 GC 必须达到不可满足的高水位。

断言既要求出现 `running auto-GC`，也要求 G 被删除，避免误把“根本没发生 GC”当成保活正确。这里没有模拟真实的 `ENOSPC`，因此不能由它推导空间预留或无限容量保证。

**不要把这个环境变量全局 export 给默认 store 命令，也不要去掉独立 store URI。** 临时目录可以通过 `TMPDIR` 指定，正常退出后由 `TemporaryDirectory` 清理。

### 7.4 SSH 替身仍使用真实 Nix 协议

脚本生成一个临时的 `ssh` 可执行文件，并放在测试子进程的 PATH 前面。它不连接真实主机，而是执行指定接收版本的真实 `nix-store --serve --write` 或 `nix-daemon --stdio`，并显式传入目标临时 store。

替身必须处理两项 OpenSSH 行为：

1. Nix 会发起 `ssh -O check` 检查已有 master，替身对此返回失败，而不是启动一个等待二进制输入的 serve 进程。
2. Nix 的普通 SSH 启动流程期待 `LocalCommand` 输出 `started`，替身必须先输出并 flush 这一行，再 exec Nix 接收程序。

测试使用 `gc-test` 假主机名。**不要随意改成 `localhost`**：已检查的 Nix 对它有绕过 SSH 的特殊处理，可能不再调用此替身。

因此测试覆盖真实的两种 Nix 协议和进程生命周期，但不覆盖真实网络、SSH 认证、反向转发和断线重连。

### 7.5 成功不等于永久保留

默认成功模式检查 A 和 R 存在，然后在复制进程退出后对目标临时 store 执行 GC，要求它们立刻消失。它们没有 profile root，消失正说明临时保护已经释放，不存在“一天内不能回收”的新政策。

原生 cache 模式则先确认 `--realise` 退出后 root 仍保护 A、R；删除持久 root 后，再确认立即可回收。这证明了从临时保护到持久保护的交接，而不是只测下载成功。

## 8. 从仓库重新构建并运行实验

以下命令从仓库根目录执行。它们不部署系统，不连接真实服务器，不对默认 store 手工执行 GC。构建可能需要网络或已准备好的构建输入；没有公网不是凭空获得缺失源码、编译器和依赖的能力。

### 8.1 准备输入与 Python

```bash
export REPO="$PWD"
nixpkgs_expr='let
  f = builtins.getFlake ("path:" + builtins.getEnv "REPO");
  p = builtins.getAttr builtins.currentSystem f.inputs.nixpkgs.legacyPackages;
in'

python=$(nix build --impure --no-link --builders '' --print-out-paths \
  --expr "$nixpkgs_expr p.python3.out")

stock34=$(nix build --impure --no-link --builders '' --print-out-paths \
  --expr "$nixpkgs_expr p.nixVersions.nix_2_34.out")

stock35=$(nix build --impure --no-link --builders '' --print-out-paths \
  --expr "$nixpkgs_expr p.nixVersions.nixComponents_2_35.nix-cli.out")

openssh=$(nix build --impure --no-link --builders '' --print-out-paths \
  --expr "$nixpkgs_expr p.openssh.out")
```

这里获取 Python 是因为实验机器的默认 PATH 没有 `python3`，不能把一个已有的个人环境当成复现前提。官方 `nix-cli` 输出足以提供本测试用到的程序，原生方案不使用 `nix-gc-safe`。

### 8.2 获取当前使用的原版 Nix 包

```bash
official=$(nix build --impure --no-link --builders '' \
  --max-jobs 1 --cores 4 --print-out-paths \
  --expr "$nixpkgs_expr p.nixVersions.nix_2_35.out")
"$official/bin/nix" --version
```

在较大的控制机上构建，按本机资源降低 `--cores`。`--builders ''` 强制不把这次编译发往小容量生产节点；这里没有构建整个系统或内核。包的模块化依赖和上游检查可能仍需要较长时间。

表达式明确选择 `.out`。聚合 Nix 包默认可能同时打印 `man` 与 `out` 两个输出；不选择 `.out` 就把多行输出赋给变量，随后拼接 `/bin/nix` 会成为一个不存在的路径。历史自定义包已经删除，不再提供该包的当前构建入口；第 5 节仅保留代码解释。

不要手写某次实验的 `/nix/store/...` hash 当永久标识。动态获取输出路径，保留 `flake.lock`，并检查实际版本。`--no-link` 的构建输出以后可能被普通 GC 回收，需要时可重新构建。

### 8.3 当前版本的回归命令

```bash
"$python/bin/python3" -B tests/nix-copy-gc-test.py "$stock34" --expect-failure
"$python/bin/python3" -B tests/nix-copy-gc-test.py "$stock35" --expect-failure
"$python/bin/python3" -B tests/nix-copy-gc-test.py "$stock35" --native-cache
```

前两组应在三种协议打印 `reproduced deletion of a reused dependency`，第二组明确证明只升级官方 2.35 不修复普通 push。第三组使用未修改的官方 Nix，应打印原生 cache 保护、无关垃圾回收和 root 释放成功。当前 A/B/C 方案接受这些失败窗口，所以不能对原版普通 copy 要求历史补丁的正向结果。

历史成功测试和 `--client` 混合版本模式仍可用于已有的历史构建产物，但它们不再是当前源码能够直接重建的自定义包；不要把测试期望改成忽略错误，以此声称阈值解决了根因。

测试脚本没有填满实际磁盘，但独立 store 状态、NAR 和构建工具仍需可用空间。若设置 `TMPDIR`，先确保该目录存在且可写，例如本次实验使用的 `/tmp/kilo`；不要以 root 手工删除不属于这次实验的临时目录。

### 8.4 检查真正的目标配置

```bash
nix eval --impure --json --expr '
  let
    f = builtins.getFlake ("path:" + builtins.getEnv "REPO");
    names = ["tyo0" "tyo1" "hkg0" "hkg5" "sjc0" "fra1" "cu" "fra0"];
  in builtins.listToAttrs (map (name:
    let c = f.nixosConfigurations.${name}.config;
    in { inherit name; value = {
      version = c.nix.package.version;
      package = c.nix.package.outPath;
      minFree = c.nix.settings.min-free;
      maxFree = c.nix.settings.max-free;
      gcEnvironment = c.environment.variables;
    }; }
  ) names)
'
```

当前期望是八台选择官方 2.35 包，`minFree=1073741824`、`maxFree=32212254720`，环境变量 `NIX_GC_A=4294967296`。A 只用于启用 minimal 的节点，`fra0` 不会因为导出 A 就自动增加部署后清理脚本。

### 8.5 Git flake 的未跟踪文件问题

正常 Git flake 的 `.#` 入口不会自动包含未跟踪文件。历史自定义包未纳入 Git 时曾出现缺少包或 patch 的风险；现在已经删除自定义包依赖，正常部署不再需要这两个文件。

本轮验证使用 `path:` 来源，避免误把文件跟踪问题当成包构建问题。但不能依赖这种方式过滤 Git 忽略文件，使用前检查源码目录中没有不应进入 Nix store 的私钥或其他秘密。

准备按原 Git flake 入口部署时，应只纳入本次文件，而不是 `git add .`：

```bash
git add -- nixos/modules/base/nix.nix \
  nixos/modules/optimize/minimal.nix \
  tests/nix-copy-gc-test.py docs/nix-copy-gc-architecture.md docs/README.md
```

这是读者的准备步骤，不表示本次已执行暂存、提交或推送，也不应顺带处理其他人的 Zotero 修改。

如果先前已经暂存了自定义包和补丁的添加，删除工作树文件不会自动更新 index。应同步这些删除，例如在仍存在对应 index 条目的情况下执行 `git add -u -- pkgs/nix-gc-safe/`；不要提交仍包含旧补丁的暂存快照。本次没有擅自修改已有暂存区。

## 9. 方案 B：原生拉取为什么不需要源码补丁

原生流程是：

```text
控制机先构建并 root 新系统
  -> 发布完整闭包到 binary cache
  -> 目标机通过 substitution realise 新系统
  -> 同一个 realise 进程建立 staging GC root
  -> system profile 接手
  -> activation 完成后清理 staging root
```

`nix-store --realise` 的 substitution goal 处理路径及其依赖，不沿用普通 push 那个“查到 A 有效后跳过、不登记保活”的流程。本次官方 2.35.3 的实验确认：已有无 root 的 A 在导入 B 的 auto-GC 中被保留，G 被回收。

`--add-root` 与 realise 放在同一个命令中，是避免显式拆开操作空窗的基本要求。不能先单独 realise、等进程退出后才另起命令建 symlink。在路径仍有效且 root 已被 GC 正确观察的条件下，staging root 可以保护闭包并供后续 profile/activation 使用；同一个命令不等于已经证明所有外部 GC 时序安全。

若采用这套流程，目标可以只选择原版包：

```nix
nix.package = pkgs.nixVersions.nix_2_35;
```

这行配置本身不修复旧 push 命令。当前仓库已经选择原版包配合 A/B/C 阈值缓解，但没有自动改写 Colmena/nixos-rebuild，也没有默认启用本节的 cache 拉取流程。

### 9.1 本地实验的准确证据

`--native-cache` 先用 `nix copy --to file://...` 发布完整闭包，再对目标独立 store 执行：

```text
nix-store --realise R --add-root staging --indirect
  --option substituters file://cache
  --option min-free 300 --option max-free 10000
```

断言依次验证：GC 确实发生；G 消失；A、R 存在；realise 进程退出后再 GC，A、R 仍存在；删除 staging 后再 GC，A、R 消失。

这证明了官方 Nix 的核心生命周期，不证明真实 SSH、NAR 签名部署、profile 切换或开机回滚已经完成验收。本实验的 `toFile` 对象采用内容寻址；生产系统不能因此省略签名和信任校验。

### 9.2 不能省略的外部 GC 并发交接风险

源码复核还发现一个不能由上述顺序实验排除的时序。锁定的官方 2.35.3 中，`IndirectRootStore::addPermRoot` 是先 `addTempRoot`，再创建 root symlink，再 `addIndirectRoot`；`LocalStore::addIndirectRoot` 只创建间接 symlink，没有尾部 GC 同步 barrier。`FdLock` 的共享锁在调用结束时释放。GC 先扫描持久 roots，再扫描临时 roots；LocalStore 析构只等待自身 auto-GC，不等待另一个进程的全部 GC。

因此静态上需要考虑：

```text
最后一次临时 root 登记结束
外部 GC 启动并扫描持久 roots，此时 staging 尚未出现
realise 创建 staging 并退出，临时 root 文件被释放/移除
外部 GC 再扫描临时 roots，也已看不到这个进程
本轮 GC 可能没有观察到应保留的根
```

官方 2.35 的删除前重查，不能自动补救从未进入该轮保护集的 root。测试在 realise 退出后才另起 GC，验证的是顺序交接，不覆盖这个并发窗口；这里没有声称已做出其确定性压力复现。

若要求严格覆盖外部 GC 并发，仍需证明“持久 root 创建后、临时保护释放前”的同步，例如保持 root-owner 连接并完成正确的后置 ACK/barrier，或采用另一个已经验证的原生实现。本文没有实现该额外机制，也没有追加另一个源码补丁。

所以方案 B 的操作例子不是“仅配置即可解决全部严格约束”的已验收生产方案。需要单独协调外部 collector，且不能把单纯暂停 timer 当成排除了其他客户端触发的 GC。realise 内部的 auto-GC 仍可运行，但不能由它的测试结果推导所有其他 collector 的行为。

## 10. 无公网 IP 的发布与拉取流程

下面是待部署流程示例，不是本轮已经执行的操作，也没有解决第 9.2 节的所有外部 GC 交接时序。两端需有可用 SSH 通路和所需程序，接收端先具备官方 2.35 的 GC 同步修复。首次从旧版本引导升级仍有旧行为，不能宣称首次更新已经受新版保护。

### 10.1 控制机准备结果与签名

先按方案 B 选择原版 Nix，再构建目标系统，保留结果 symlink，不使用无 root 的 `--no-link` 结果作为长期发布源。控制端准备、构建、路径获取、签名与导出应在同一个启用 fail-fast 的 Bash 过程内执行；下面分块是为了说明步骤，不能忽略失败后继续读旧 result：

```bash
set -euo pipefail
host=cu
keydir="$HOME/.config/nix/native-deploy"
nix build --out-link "./result-native-$host" \
  ".#nixosConfigurations.$host.config.system.build.toplevel"
system=$(readlink -f "./result-native-$host")
```

生产 cache 使用 NAR 签名。以下密钥初始化只应人工执行一次，不把私钥写进仓库、cache 目录或日志：

```bash
umask 077
keydir="$HOME/.config/nix/native-deploy"
mkdir -p "$keydir"
test ! -e "$keydir/cache.sec" || exit 1
nix key generate-secret --key-name native-deploy-1 > "$keydir/cache.sec"
nix key convert-secret-to-public < "$keydir/cache.sec" > "$keydir/cache.pub"
```

通过已验证身份的渠道在目标端信任公开的 `native-deploy-1:...` 值。本文不会提供一把真实私钥，也不建议用 `require-sigs=false` 省略安全检查。

已有密钥的日常发布跳过初始化块；发布前在同一个 fail-fast Bash 中检查密钥、为源闭包签名，再导出到控制机普通目录：

```bash
test -s "$keydir/cache.sec"
nix store sign --recursive --key-file "$keydir/cache.sec" "$system"
cache=$(mktemp -d)
nix copy --to "file://$cache" "$system"
printf 'system=%s\ncache=%s\nopenssh=%s\n' "$system" "$cache" "$openssh"
```

构建失败就停止，不继续读取可能残留的旧 symlink；签名失败也必须停止，不继续导出。多终端示例使用上述打印的实际路径，shell 变量不会自动出现在另一个终端。

cache 中的 NAR 是普通发布文件，不是目标机又一份未 rooted 的 store 闭包。无需先把完整 cache 上传并存放到 10 GB 接收机；它可以在控制机上服务，避免目标先保存一个大归档再展开。

### 10.2 两个控制机终端保持运行

终端一沿用准备结果的 shell，HTTP 只绑定控制机 loopback，使用第 8 节准备的 Python：

```bash
"$python/bin/python3" -m http.server 18080 --bind 127.0.0.1 --directory "$cache"
```

终端二，根据上一节输出设置 `openssh` 路径，沿已有 SSH 通路反向转发。先在 `native-deploy-known-hosts` 中准备通过可信渠道核对的目标 host key，条目必须匹配实际 hostname 和端口：

```bash
"$openssh/bin/ssh" -N -T -o ExitOnForwardFailure=yes \
  -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$HOME/.ssh/native-deploy-known-hosts" \
  -o ForwardAgent=no -o ControlMaster=no -o ControlPath=none \
  -R 127.0.0.1:18081:127.0.0.1:18080 tippy@cu.dn42
```

目标的 `127.0.0.1:18081` 通过 SSH 到达控制机的 `127.0.0.1:18080`。控制机没有公网 IP 没有关系；无需开放控制机 HTTP 入站端口。

使用正常部署用户，不用带 `ForceCommand`、禁止 forwarding 的 `nix-ssh` 服务账号。需要服务端允许该用户 TCP forwarding，并确认 `GatewayPorts` 不强制把 reverse listener 绑定到公网；默认 `no` 是合适的。`ExitOnForwardFailure` 可以及时发现端口冲突或 forwarding 被拒绝，不能替代检查 cache 文件和签名。

隧道和 HTTP 服务必须在整个拉取期间保持运行。不要绕过 SSH 主机身份校验来“修复”连接问题。DNS、DN42、代理路由与 SSH 自身故障不由 GC root 修复。

这些参数不能省略：仓库现有 Home Manager SSH 配置有 `StrictHostKeyChecking=no`、`UserKnownHostsFile=/dev/null`、agent forwarding 和连接复用设置。这里使用原生 OpenSSH、显式校验文件、不转发 agent，也不复用可能此前未经校验的 master。未知 key 应失败；不要把未经核对的 `ssh-keyscan` 输出直接当成信任依据。另一个目标登录终端也应使用相同的身份校验与禁用复用参数。

loopback 只限制网络暴露，两端机器的其他本地用户仍可能访问这个 HTTP cache。NAR 签名提供真实性/完整性，不是访问控制或保密机制；SSH 加密传输也不改变 loopback 本地访问这一点。只在可信主机环境使用，或者另做鉴权/隔离，且不要把秘密放入 Nix store 或发布目录。

### 10.3 目标机交接到 profile

在目标机上先核对 cache 可访问：

```bash
nix store ping --store http://127.0.0.1:18081
```

下面以目标机普通用户执行 `sudo bash` 为例。把变量改成该次构建的准确路径与已经核对的公钥；这些占位值不能直接部署：

```bash
system=/nix/store/REPLACE-WITH-ACTUAL-nixos-system-cu
public_key='native-deploy-1:REPLACE-WITH-VERIFIED-PUBLIC-KEY'

sudo bash -s -- "$system" "$public_key" <<'SH'
set -eu
system=$1
public_key=$2

# 仅协调遵守此锁的原生部署流程，GC 不获取它。
exec 9>/run/lock/nix-native-deploy.lock
flock -n 9 || { printf 'Another deployment is in progress\n' >&2; exit 1; }

root_dir=$(mktemp -d /nix/var/nix/gcroots/native-deploy.XXXXXX)
staging="$root_dir/system"
cleanup() {
    rm -f -- "$staging"
    rmdir -- "$root_dir" || true
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

timeout 20m nix-store --realise "$system" --add-root "$staging" \
    --option substituters http://127.0.0.1:18081 \
    --option trusted-public-keys "$public_key"

nix-env -p /nix/var/nix/profiles/system --set "$system"
"$system/bin/switch-to-configuration" switch
SH
```

正常顺序下，staging root 在 realise 进程退出前就存在，并在 profile 设置与 activation 期间继续存在。最终 EXIT cleanup 删除它，不是等待一天。第 9.2 节的外部 GC 交接风险仍需单独处理；不能因为文件存在就宣称所有并发时序已验证。generation 保留仍由原有策略管理。

临时 override 仅指定这次操作使用的 loopback cache 和已验证公钥，不把一个通常不存在的隧道地址永久塞进所有构建的全局 substituters。

示例里的部署锁不被 GC 获取，超时也不要求 GC 达到 `max-free`。`timeout` 限制客户端等待，不等于强制原子取消 daemon 内所有工作。`SIGKILL`、断电等可能留下 staging root，需确认没有活动部署后检查并清理对应目录，不能凭目录年龄自动删除。

这个锁只让遵守它的方案 B 实例互斥。原有 Colmena、`nixos-rebuild` 或其他 profile 修改命令不会自动获取它，不能与本流程并发后仍声称全机部署已经串行化。

profile 更新和 activation 不是整个系统的数据库事务。activation 失败时 profile 可能已经指向新系统；本示例不承诺自动回滚。旧运行/启动系统的保护、失败后的恢复操作必须按实际状态判断。

完成并验证后再关闭隧道、HTTP 服务及清理本次 cache。保留或删除控制机 result symlink 同样按发布保留策略处理，不把它和目标机 generation 混为一谈。

## 11. 实际遇到的问题与解决办法

| 问题                                         | 判断与解决                                                                                           |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| 最初过早认定缺少全部临时 roots               | 读源码后确认单路径导入已有 root；通过已有 A 的实验定位真正缺失的是完整复制查询保活                   |
| 以为只停 timer 就能解决                      | 枚举 auto-GC、timer、activation 三个入口，不误停必要回收                                             |
| 把 generation 删除天数当成 store 路径保护期  | 区分删 profile roots 和回收不可达路径；不加入一天保留新路径的策略                                    |
| Colmena 补丁不通用                           | 撤销前端实现，方案 A 使用共同 store 层，方案 B 使用原生流程                                          |
| 误以为升级/Lix/git 包自动覆盖所有问题        | 分别核查 GC 同步、copy 保活、协议和激活交接，不用版本新旧代替证据                                    |
| patch 路径或 hunk 不准确                     | 核对组件 source root；修正 hunk 行数并用 `--fuzz=0` 检查，避免依赖模糊匹配                           |
| 只给外层 Nix 包加 patch 可能没改到库         | 使用模块化包的 `overrideScope`，构建真实 `nix-store` 组件                                            |
| 配置目录混入构建逻辑与 patch 文件            | 移到 `pkgs/nix-gc-safe`，配置仅留一行包选择                                                          |
| 默认 PATH 没有 Python                        | 从锁定 nixpkgs 获取 Python，不要求使用个人系统中的绝对路径                                           |
| 测试的 `ssh` 文件与 `ssh` 目标目录撞名       | 目标改为 `store-ssh`、`store-ssh-ng`，替身仍为 `ssh`                                                 |
| SSH 替身卡住或 handshake 错位                | 实现 `-O check` 和 `started` 启动信号，保留真实二进制协议                                            |
| 源端也可能被 fake-free 干扰                  | 先为源 R 创建持久 root，让实验只关注目标缺陷                                                         |
| 早期手工查看了旧输出 hash                    | 后续一律从构建 stdout 获取路径，并核对目标配置选择，布局迁移后确认仍指向相同已验证包                 |
| 聚合包输出多个路径，shell 变量不能当目录使用 | 复现命令明确选择 `.out`，避免把 `man` 和 `out` 拼成一个多行路径                                      |
| 后台命令的 `$` 被宿主包装器再次展开          | 构建表达式改用 `builtins.getAttr builtins.currentSystem`，不嵌入易被误处理的 shell 插值              |
| 长构建被中断且看不到进度                     | 查询受管理构建状态与 `nix log`，确认已完成结果再测试；不把空输出当成成功，也不反复重编译             |
| Git flake 看不到新文件                       | 用 `path:` 验证并说明 source 安全边界；正常部署前只纳入指定文件                                      |
| SSH 没有输出、DNS 失败或未知主机密钥         | 不推断远端成功，不绕过身份检查；区分 transport 故障与 GC 缺陷                                        |
| 推送机没有公网                               | 使用 SSH reverse forwarding 的 loopback cache，不在目标存完整发布归档                                |
| 原生 root 顺序实验不足以证明任意并发交接     | 核实 addPermRoot、锁释放和 GC 扫描顺序，在第 9.2 节明确外部 collector 风险，不冒充已实现严格 barrier |
| 仓库 SSH 默认不校验且可能复用旧 master       | 运维示例显式使用原生 OpenSSH、核对的 known-hosts、严格校验、禁用 agent forwarding 和连接复用         |
| 构建/签名失败后可能继续发布旧结果            | 控制端步骤在同一个 fail-fast Bash 过程内执行，仅成功后读取 result 并导出                             |

没有为了通过测试修改用户的 `zotero-sync-server.nix`，也没有把测试超时、部署示例或历史试验代码偷偷加入生产 GC 配置。

## 12. 已验证与未验证的边界

### 12.1 已完成的证据

以下复制保活的正向证据属于历史补丁实验，不代表现在的原版 Nix 具有同一保证。最新工作树已经删除补丁，选择的是已接受残余风险的 A/B/C 阈值策略。

- Nix 2.34.9 和未修改的官方 2.35.3 的三个复制协议均复现已有依赖被删除和 `is not valid` 失败。
- 修复的 Nix 2.35.3 三种协议均保留依赖，同时删除无关垃圾；会话退出后无 root 的新路径立即可回收。
- 旧 2.34.9 客户端到修复接收端的 `ssh`、`ssh-ng` 均通过。
- 官方未修改的 2.35.3 的本地 cache + realise + 持久 root 交接实验通过。
- 修复包构建完成；上游 store 测试报告 726 项通过，另有一个上游原本禁用的测试，不能声称它也运行了。
- 八台目标配置均求值到修复包，水位未改变；文件布局迁移后包路径仍为同一已构建结果。
- 本次已运行格式与 diff 检查；新增 test 不是自动注册的 flake check。

历史实验中，`hkg5` 的 Nix 为 2.34.9，`df -h` 显示分区约 `8.7G`、空闲约 `3.1G`；显示值有四舍五入，不能当精确字节数。其日志看到定时 GC，但不足以证明用户现场的完整循环只由一种原因造成。其他节点的无输出、连接失败不能当作版本或部署证据。

### 12.2 没有承诺的事项

- 没有生产部署、重启或对实际服务器手工 GC。
- 没有测试真实反向 SSH 转发、签名发布和完整 profile/activation 操作。
- 方案 A 不保护 copy/build 结束到下一个命令之间的空窗；方案 B 的 staging root 用于正常顺序下跨进程保留，但其外部 GC 并发交接尚不构成严格保证。
- 没有空间预留、部署前容量准入算法、新的生产 retry 上限或 GC 看门狗。
- 正在保护的当前系统、启动系统、新闭包和导入开销若本来就放不下，仍可能报 `ENOSPC`。GC 不能创造容量。
- 不保证异常 GC 进程、损坏 socket、内核 I/O 卡死时永不等待；结论是不引入新的 push/GC 锁环。
- 不将任意第三方写 store、提前断开的会话和所有连接池配置视为已经验证。
- 首次部署新版仍由旧接收端处理，必须单独安排引导升级；不能用新配置求值结果证明旧 daemon 已经更新。

## 13. 更新、验收与维护清单

1. 当前用户选择的是分离阈值、删除补丁并接受残余风险。若另行采用 cache 拉取或恢复历史保活实现，应明确不同保证，不把它们混用为同一个承诺。
2. 更新 nixpkgs 后检查 `nix_2_35` 实际版本与 GC 同步行为；当前不再维护源码补丁和自定义组件。
3. 检查顶部 A/B/C 环境变量与生成的 B/C 设置、A 激活常量。调 B 不应隐式改变 A；删除补丁后负向复制实验仍可能成立。
4. 对方案 B 使用未修改包运行 `--native-cache`；真实验收另测签名、公钥、SSH forwarding、stage/profile 交接和失败恢复。
5. 用目标配置求值确认包选择，而不是只看 PATH 中一个 `nix --version`。部署后还应核对正在运行的 daemon，避免 shell PATH 与服务版本不一致。
6. 保持 GC roots 的明确所有权；不要因为磁盘紧张就手工删除活动进程的 temp-root 文件或未知 staging root。
7. 若以后上游稳定版本完整解决普通复制保活，再运行三协议和生命周期实验确认；当前补丁已经主动删除，不能把删除本身视为问题已修复。

上游参考：

- [Nix 2.35.3 的 `LocalStore`](https://github.com/NixOS/nix/blob/2.35.3/src/libstore/local-store.cc)
- [Nix 2.35.3 的 GC 与临时 root 同步](https://github.com/NixOS/nix/blob/2.35.3/src/libstore/gc.cc)
- [Nix 2.35.3 的持久 root 创建顺序](https://github.com/NixOS/nix/blob/2.35.3/src/libstore/indirect-root-store.cc)
- [动态临时 root 删除竞态修复 PR #15992](https://github.com/NixOS/nix/pull/15992)
- [复制集合预保活的上游工作 PR #16113](https://github.com/NixOS/nix/pull/16113)
- [原生 `nix-store --serve`](https://nix.dev/manual/nix/2.24/command-ref/nix-store/serve)
- [原生 `nix-store --realise`](https://nix.dev/manual/nix/2.28/command-ref/nix-store/realise)

PR 的存在、master 的某个修改或更高的版本号，都不能代替实际检查锁定源码和运行本仓库的复现实验。

## 14. hkg5 组件与完整依赖大小

本轮分析使用本机仍有效的已构建版本：

```text
/nix/store/wbblvdd6mwzhsj64nbk8906vx38r5jxz-nixos-system-hkg5-26.11pre-git
```

它的完整闭包为 **1132 个 store 路径、3192661128 NAR 字节，约 2.973 GiB / 3044.8 MiB**。这不是新 A/B/C 配置的整机重新构建结果，也不是直接测得的 hkg5 物理磁盘占用。

### 14.1 程序输出本身、依赖与合计

每行的依赖集合内部已经去重，合计包含程序本身。不同组件之间仍大量共享依赖，因此不能把各行相加，也不能认为删除一个组件就必然节省它的完整合计。

| 组件                             | 自身 MiB | 递归依赖 MiB | 合计 MiB |
| -------------------------------- | -------: | -----------: | -------: |
| Janus Gateway 1.4.3              |      4.8 |        484.0 |    488.8 |
| Fish 4.9.3                       |     38.5 |        271.6 |    310.2 |
| FFmpeg 9.0.2 lib                 |     34.5 |        270.3 |    304.8 |
| VictoriaMetrics 1.154.0          |    246.2 |         39.2 |    285.4 |
| nixos-anywhere 1.13.0            |     <0.1 |        282.3 |    282.4 |
| networkd-dispatcher 2.2.4        |     <0.1 |        273.3 |    273.3 |
| Python 3.14.8 env                |      0.2 |        270.9 |    271.1 |
| libnice 0.1.24                   |      0.5 |        264.7 |    265.2 |
| nixos-install-tools              |     <0.1 |        264.1 |    264.1 |
| Neovim 0.12.6                    |      0.6 |        257.4 |    258.0 |
| Restic 0.19.1                    |     48.4 |        204.2 |    252.6 |
| GStreamer 1.28.7                 |      6.2 |        242.2 |    248.4 |
| Python 3.14.8                    |    137.1 |         75.4 |    212.5 |
| Traefik 3.7.15                   |    176.4 |          2.7 |    179.1 |
| rclone 1.75.2                    |    106.8 |         53.3 |    160.1 |
| sing-box 1.14.3                  |    107.0 |         52.3 |    159.3 |
| Nextcloud Spreed Signaling 2.1.1 |     68.4 |         39.2 |    107.6 |
| trafficcontrol 8.0.2 t3c         |     65.3 |         39.2 |    104.4 |

`<0.1` 是显示精度，不是没有内容。Fish completions 的闭包与 Fish 本体高度重合，没有单独重复列为另一份 310 MiB。

### 14.2 服务单元会引入更多东西

一个 service 除程序外，还可能引用 pre-start 脚本、配置生成器、通用工具、证书工具等。服务单元闭包比程序输出更能反映部署依赖：

| 服务单元                            |           完整闭包 MiB |
| ----------------------------------- | ---------------------: |
| atc-t3c-sync                        |                  584.4 |
| janus-gateway                       |                  573.8 |
| atc-edge-health / atc-edge-recovery | 各 466.6，重叠不应相加 |
| trafficserver                       |                  454.8 |
| prometheus-vmagent                  |                  422.3 |
| nextcloud-spreed-signaling          |                  394.5 |
| traefik                             |                  352.5 |
| coturn                              |                  348.2 |

整体 `system-path` 为 1589.7 MiB，Home Manager generation 为 973.2 MiB，它们是集合，不是额外可直接相加的独立组件。DBus unit 的约 1590.4 MiB 引用包括通用 system-path，不能解释成 DBus 二进制本身有 1.6 GiB。

如需判断真正可节省多少，应该比较“删除该功能后重新构建的完整系统闭包”与旧闭包的集合差，而不是直接删目录或累加上表。本次没有关闭任何 hkg5 服务。

### 14.3 如何只读复现闭包排序

在包含该已构建版本的 store 上，以下查询只读 SQLite，不执行 GC，不创建新的 Nix store 会话。修改路径前先确认目标版本仍有效；只有目标端有某个版本时，需要在相应机器上统计。

```bash
sudo sqlite3 -readonly -header -column /nix/var/nix/db/db.sqlite "
WITH RECURSIVE
system(id) AS (
  SELECT id FROM ValidPaths
  WHERE path='/nix/store/wbblvdd6mwzhsj64nbk8906vx38r5jxz-nixos-system-hkg5-26.11pre-git'
  UNION
  SELECT reference FROM Refs JOIN system ON referrer=system.id
),
deps(component,id) AS (
  SELECT id,id FROM system
  UNION
  SELECT deps.component,Refs.reference
  FROM deps JOIN Refs ON Refs.referrer=deps.id
)
SELECT root.path,
       ROUND(root.narSize/1048576.0,1) AS own_MiB,
       ROUND((SUM(child.narSize)-root.narSize)/1048576.0,1) AS deps_MiB,
       ROUND(SUM(child.narSize)/1048576.0,1) AS total_MiB
FROM deps
JOIN ValidPaths root ON root.id=deps.component
JOIN ValidPaths child ON child.id=deps.id
GROUP BY deps.component
ORDER BY SUM(child.narSize) DESC
LIMIT 40;
"
```

`UNION` 对每个组件的递归 references 去重，避免同一依赖走多条路径时重复计数。全量排序最前面会包括系统、etc、system-units 和 Home Manager 等聚合集合；筛选实际程序输出时需明确这一口径，不应把集合大小称作程序自身大小。

这些数值是 NAR 逻辑大小，文件系统压缩、硬链接共享、分配块和元数据都会影响物理占用。它也不包含运行时数据库、容器镜像、日志、swap 等非 store 数据；完整闭包大小更不等于每次更新都要传输或新增的字节数。

## 15. minimal 的 Shell、编辑器和安装工具精简

本次在 minimal 中关闭系统 Fish，并同时把默认用户 shell、tippy 的显式登录 shell 改为 `bashInteractive`。Home Manager 也关闭 Fish 及 Fish 插件包，启用 Bash；否则只关闭系统选项仍会由用户配置重新引入 Fish。

minimal 原先强启轻量 Neovim，并把 `vim` 别名指向它；现在关闭 nvf/Neovim、保留 base 中真正的 Vim，默认 `EDITOR`、`VISUAL` 为 `vim`。Home Manager 的 `MANPAGER="nvim ..."` 也只在非 minimal 中保留，避免留下不存在的 pager。非 minimal 的 Fish/nvf 默认行为保持不变。

系统的五项 `documentation` 关闭设置此前已经存在，继续保留；额外关闭 Home Manager 的 man 程序、HTML/manpages/JSON 手册。关闭安装选项并不意味着所有包主输出中内嵌的文档也能被剥离。

```nix
nixpkgs.flake = {
  setNixPath = lib.mkForce false;
  setFlakeRegistry = lib.mkForce false;
};
```

两个自动 pin 开关在 minimal 中关闭；已有 `nix.settings.nix-path = lib.mkForce []` 也保留，以覆盖 base 的手写 NIX_PATH。远端 `self` registry 仍用于版本指标，不把它误认为自动 nixpkgs pin。

全机器的 base 常驻包列表删除 `nixos-anywhere` 和显式 `nixos-install-tools` 聚合包。保留按需安装脚本与 flake 包导出；删除目标机常驻包不等于删掉控制端安装能力。非 minimal 主机仍可使用 NixOS 内置的个别安装工具；minimal 已有 `system.disableInstallerTools=true`，不再被显式聚合包重新引入。该聚合包也不包含 `nixos-rebuild`，不能将二者混淆。

### 15.1 已确认的依赖链

```text
Janus -> FFmpeg lib
  具体引用文件：bin/janus-pp-rec（录制后处理程序）

Janus -> libnice -> GStreamer -> Python
  libnice 中具体引用文件：lib/gstreamer-1.0/libgstnice.so

旧 hkg5 system-path -> Fish -> Python

Nix 2.35.3 本身不依赖 Python 运行时
```

Janus 包默认启用 `--enable-post-processing`，FFmpeg 被其录制后处理程序引用，不等于 WebRTC 转发进程正在执行视频转码。libnice 提供 Janus 所需的 ICE/STUN 核心，不能直接删掉这个库；它默认还构建 GStreamer 插件，因此把 GStreamer 引入了包闭包。

可以研究只关闭 Janus 后处理、只禁 libnice 的 GStreamer 插件或拆分对应输出，但需要重新构建变体、验证 Janus/Talk 功能和闭包。当前 nixpkgs 的 libnice 包把 `gstreamer=true` 写在 meson flags 中，没有独立的现成 NixOS 开关。本次不修改这些服务功能，不声称删除工具列表中的名字就能去掉传递依赖。

Python 还被 ATC 健康检查/恢复/启动脚本、networkd-dispatcher、pssh、replace-secret 及相关 Python 环境使用。关闭 Fish 只去掉其中一条来源，不会删除服务仍然需要的解释器。Nix 的构建工具可能使用 Python，也不能据此推断 Nix 二进制有 Python 运行时依赖。

### 15.2 构建验证

已在控制机本地构建，没有向 hkg5 部署：

```text
新结果：/nix/store/xv65i48mzvsca44f0hrwc125wy9v0is0-nixos-system-hkg5-26.11.20261023.3ec6363
旧闭包：1132 路径，3044.8 MiB，2.973 GiB
新闭包：1002 路径，2911.2 MiB，2.843 GiB
差值：约 133.6 MiB（NAR 逻辑大小）
```

比较的旧结果是第 14 节已有部署构建，包含此前包/配置状态的差异；不能把全部差值归因于某一个开关。真实新闭包检查确认没有 Fish、Neovim、nixos-anywhere、nixos-install-tools，仍包含 Vim、Python、FFmpeg 和 GStreamer。新 generation 需要部署后才会改变登录 shell 和运行服务，旧 generations/用户 profile 不会因此自动消失。

复现构建：

```bash
nix build --impure --no-link --builders '' --max-jobs 1 --cores 2 \
  --print-out-paths --expr '
    let f = builtins.getFlake ("path:" + builtins.getEnv "REPO");
    in f.nixosConfigurations.hkg5.config.system.build.toplevel
  '
```

该命令沿用第 8 节导出的 `REPO`，构建时仍需确保源码目录没有不应进入 store 的秘密。closure 统计可沿用第 14 节的只读查询并替换系统路径。不要把单个包的依赖闭包数字直接相加当成这次实际节省空间。
