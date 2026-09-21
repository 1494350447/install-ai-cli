# 把 DeepSeek Harness (dsh) 整合进 install-ai-cli.sh — 设计文档

日期：2026-09-22
状态：已实现（v1.2.0），待真机验证

## 1. 背景

`deploy.sh` 是一份 612 行的 DeepSeek Harness 部署脚本，管理 dsh 的完整生命周期（clone 源码 → pnpm 构建 → 补齐原生产物 → 后台常驻 → 停止/查看/重置）。

目标是把 dsh 并进 `install-ai-cli.sh`，让后者成为唯一的 dsh 入口。

### 为什么不能直接合并

两者不是同一类东西：`install-ai-cli.sh` 装的是**一次性 CLI 二进制**，装完即结束、不写脚本所在目录、可在任意位置执行（含 `curl | bash`）；`deploy.sh` 是**带状态的服务管理器**，写 PID 文件、日志目录、端口，且所有状态路径都基于 `BASH_SOURCE` 解析出的脚本自身目录。

`ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` 在 `curl | bash` 场景下会退化——`BASH_SOURCE` 为空，`ROOT_DIR` 变成调用者当时的工作目录。这是第一个结构性冲突。

## 2. 关键决策

| 决策 | 选择 |
|---|---|
| dsh 形态 | **只用 npm 预编译包**，不做源码构建 |
| 管理范围 | **只装，不管运行**——不后台化、不写 PID、不管端口、不采日志 |
| 命令形态 | 命名空间 `dsh`，与另三个工具平级 |
| 安装方式 | `npm i -g @deepseek-ai/dsh`，非 `npx` |
| `all` 是否含 dsh | **不含** |
| deploy.sh | 真机验证通过后再删 |

### 为什么砍掉生命周期管理

初版设计曾包含 up / down / status / logs / verify 一整套进程管理（约 180 行）。用户的判断是「我只要能用就行」——dsh 前台跑、`Ctrl-C` 停，对个人使用完全够用，那套子系统是为不存在的需求写的。

YAGNI 在这里省掉了：状态目录设计、PID 匹配（`/proc/$pid/cmdline` 两级判定）、就绪探测宽限期、token 授权握手、SIGTERM→SIGKILL 时序。全部不写。

### 为什么用 `npm i -g` 而不是 `npx --yes`

deploy.sh 选 npx 是因为它服务于源码构建主路径，预编译只是搭车。作为独立工具融入时 npx 的代价全部暴露：预检看不见它、`--uninstall` 卸不掉它、每次调用都要重新解析 73 个包的依赖树。走 `npm i -g` 则完全复用现有的预检/卸载/升级体系。

## 3. 可行性验证（npm 元数据层面，均经实测）

- `@deepseek-ai/dsh` 在 npmmirror 上存在，`latest = 0.1.5-rc.2`，`"bin": { "dsh": "lib/bin.js" }`
- **73 条生产依赖，npmmirror 上零缺失**
- 该包共约 119 条依赖（73 生产 + 46 开发）。开发依赖中的 `@deepseek-ai/dsh-experimental-code-runtime-python` 在 npmmirror 与官方 npmjs.org 上**都是 404**。它是 **devDependency**，`npm i -g` 不装开发依赖，**不影响安装**
- **原生产物由 npm 自动下发**：原生插件 `node-addon-require-builtin` 走标准 optionalDependencies 平台包（`-linux-x64-gnu` / `-linux-arm64-gnu` / `-darwin-arm64` / `-win32-x64-msvc` …），npm 按 `os`/`cpu` 自动只装匹配的一个。**不需要任何手工补齐**，deploy.sh 中约 300 行的原生产物补齐逻辑因此全部废弃
- **web profile 所需的六个组合包全部就位**：`dsh-base`、`dsh-web-app`、`dsh-headless`、`dsh-sdk-app`、`dsh-sdk-minimal`、`dsh-acp-app` 均在依赖列表且在镜像上
- 上游要求 Node `^22.19.0 || >=24.0.0`；dsh 拒绝 `--host 0.0.0.0`

> 过程教训一则：初查时用 `tr` 粗暴切分 package.json 统计依赖，把 devDependencies 算进生产依赖，误报「国内装不上」。必须按缩进跟踪 JSON 块名做块级定位才能得到可信结论。同理，`grep -c $'\r'` 在 Git Bash 下会因管道把 LF 翻译成 CR 而假报满文件 CRLF——判断行尾要数 `tr -cd '\r' | wc -c` 或比对字节数。

## 4. 实现要点

改动集中在 `install-ai-cli.sh`，约 60 行，不动主干。三处需要判断的地方：

### 4.1 dsh 的 Node 门槛比现有检查严

现有 `node_major_installed` 只判「大版本 ≥ 22」。dsh 要 `^22.19.0 || >=24.0.0`。**Node 23.x 是关键用例**：它满足 `>=22` 却不满足 `>=24.0.0`，不单独判就会漏。

新增 `node_satisfies_dsh()`。所有比较都写在 `if` 条件里，这样无论谁在什么上下文调用都不会踩到 `set -e`。

调用点两处：`ensure_node` 里决定「已就绪」要不要提前 return；`main` 里统一判一次并告警（覆盖 `--no-node`、装完、本来就有三种情况）。**`--dry-run` 时必须跳过**——dry-run 不真装 Node，事后判定必然假报。

### 4.2 探测 dsh 版本不能跑 `dsh --version`

上游 README 明确：启动器不认识的第一个参数会被交给 profile。`dsh --version` 有可能真去拉起一个 web profile，**把预检挂死**。

`tool_version` 对 dsh 走特例：读 `$(npm root -g)/@deepseek-ai/dsh/package.json` 的 version，确定、快、无副作用；只在读不到时才退回 `--version`，且加 `timeout 5` 兜底。

### 4.3 `~/.dsh` 是 dsh 的数据目录，脚本绝不碰

`DSH_HOME` 是 dsh 自己的环境变量（默认 `~/.dsh`，由 `@deepseek-ai/dsh-home-paths` 定义），存 profile 与会话。

- `tool_config_path dsh` 返回 `${DSH_HOME:-$HOME/.dsh}/`，仅供显示
- `uninstall_tool` 的 `case` 里**不加 dsh 分支**，所以只走 `npm uninstall -g`，不会 `rm -rf` 任何东西

## 5. 已验证 / 未验证

**已验证（Windows Git Bash，v1.2.0）**
- `bash -n` 语法；`help` / `version` / `doctor` 输出
- `node_satisfies_dsh` 九个版本用例：20.11 / 22.0 / 22.18 拒绝，22.19 / 22.20 / 24.0 / 24.21 / 26.1 通过，**23.5 拒绝**
- 装、卸两条集成路径（假 node/npm + 沙箱 HOME）
- **卸载不触碰 `~/.dsh`** 的用户数据
- `all` 仍只含 codex/claude/opencode
- `--dry-run` 无副作用、无假警报

**未验证（必须在真机做）**
- `npm i -g @deepseek-ai/dsh` 实际安装
- `dsh web --host 127.0.0.1 --port 3080` 能否起来
- `dsh --version` 的真实行为（决定 4.2 的特例是否必要——保守起见先按会挂处理）

在真机验证通过之前，`deploy.sh` 不删。
