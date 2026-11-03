# install-ai-cli

[简体中文](README.md) | [English](README.en.md)

国内网络下 Linux 一键安装 **Codex CLI** / **Claude Code** / **opencode** / **DeepSeek Harness (dsh)** / **OpenClaw**。

一个不带依赖的 bash 脚本，把国内环境装这几个工具时会撞上的坑一次性填掉：Node 版本不够、npm 拉不动、平台二进制下发失败、GitHub 直连被重置。

> dsh 和 openclaw 跟前三个不是一类东西：它们**装完还得自己起**，不是敲完就结束的 CLI（dsh 是常驻 Web 服务，openclaw 是网关）。所以两者**都不并入 `all`**。详见下面各自的使用小节。

## 特性

- **预检优先**：先列出各工具的安装现状，已安装的**不会直接覆盖**，而是逐个询问「是否卸载并重新安装？」（`y` / `N` / `a` / `q`）
- **Node 三级兜底**：nvm（Gitee 镜像）→ npmmirror tarball 直装 → 明确报错并给出手动指引
- **不动你的全局 npm 源**：只在安装时用 `--registry` 临时指定。想永久改得显式加 `--set-registry`
- **不用 sudo**：全局包一律装到 `~/.npm-global`，避免 root 归属导致后续升级要 sudo
- **npm 源三级回退**：npmmirror → 腾讯云 → 官方
- **适配任意发行版**：apt / dnf / yum / pacman / apk / zypper
- **幂等**：可重复执行，不会重复装

## 快速开始

```bash
# 下载
curl -fsSL <本仓库 raw 地址>/install-ai-cli.sh -o install-ai-cli.sh

# 先体检，看清现状
bash install-ai-cli.sh doctor

# 装
bash install-ai-cli.sh codex
bash install-ai-cli.sh all
```

> 本仓库为**私有**，raw 链接直接 curl 需要带 token。公开后可去掉认证。

## 命令

| 命令 | 作用 |
|---|---|
| `codex` | 安装 OpenAI Codex CLI |
| `claude` | 安装 Claude Code |
| `opencode` | 安装 opencode |
| `dsh` | 安装 DeepSeek Harness |
| `openclaw` | 安装 OpenClaw |
| `all` | 上面三个 CLI 全装（**不含 dsh / openclaw**） |
| `doctor` | 体检：系统、Node/npm、各工具状态、网络连通性 |
| `version` | 打印脚本版本 |
| `help` | 帮助 |

`dsh` 和 `openclaw` 同样支持 `--uninstall`，且都**只摘 npm 包，不动用户数据**：`~/.dsh`（profile 与会话）和 `~/.openclaw`（配置、agents、workspace、sqlite 状态）脚本从不触碰。

单独装 `openclaw` 时，若你没显式给 `--node-major`，脚本会**自动把 Node 抬到 24**——它要求 `>=24.16.0 <25 || >=26.1.0`，默认的 22 装了也起不来。

## 选项

| 选项 | 说明 |
|---|---|
| `--reinstall` / `-f` / `--force` / `--upgrade` | 跳过询问，已装的一律卸载重装 |
| `-y` / `--yes` | 非交互：已安装的一律跳过，不重装 |
| `--uninstall` | 卸载指定工具（配置文件保留，只摘二进制） |
| `--registry <URL>` | npm 源，默认 `https://registry.npmmirror.com` |
| `--node-mirror <URL>` | Node 二进制源 |
| `--node-major <N>` | Node 大版本，默认 22 |
| `--no-node` | 跳过 Node 安装/升级（已自行装好 Node ≥ 22 时用） |
| `--native` | Claude Code 走官方 curl 安装器（默认走 npm，国内更稳） |
| `--set-registry` | 永久写入 npm 全局 registry（默认不改动全局配置） |
| `--proxy <URL>` | 走代理，如 `http://127.0.0.1:7897` |
| `-n` / `--dry-run` | 只打印将执行的命令，不落任何改动 |
| `-v` / `--verbose` | 打印每条执行的命令 |

## 已安装时的行为

脚本不会静默覆盖已有安装。先预检：

```
── 预检 ──
  codex     未安装
  claude    已安装  2.1.278     官方安装器  /home/u/.local/bin/claude
  opencode  已安装  1.18.31     npm         /home/u/.local/bin/opencode
```

然后对每个已安装的工具单独询问：

```
claude 已安装：2.1.278（官方安装器）
  是否卸载并重新安装？
    [y] 卸载并重装    [N] 跳过    [a] 其余已装的也一并重装    [q] 退出
  请选择 [y/N/a/q] >
```

- 回车 = 跳过；只有 `y`/`yes` 才重装
- `a` 让 `all` 模式下不必连问三遍
- 非交互环境（`-y`、CI、无控制终端）自动跳过并提示加 `--upgrade`
- 卸载**只删明确的路径**，每删一个都打日志；配置文件一律保留

## 支持环境

- **发行版**：Debian/Ubuntu、RHEL/CentOS/Rocky/Alma、Fedora、Arch、Alpine、openSUSE
- **架构**：x86_64、aarch64/arm64、armv7l、ppc64le、s390x
- **Node**：需 ≥ 22（脚本会自动装）。LoongArch 官方无 Node 构建，脚本会明确报错并让你用 `--no-node`
- **Node（dsh 专用）**：dsh 要求 `^22.19.0 || >=24.0.0`，比上面严。脚本会单独检查，不满足时会提示怎么处理。注意 **Node 23.x 会被拒**——它满足 `>=22`，但落在 `>=24.0.0` 之外
- **Node（openclaw 专用）**：openclaw 要求 `>=24.16.0 <25 || >=26.1.0`，比 dsh 还怪——**24.x 卡了 `.16` 的小版本下限，又把 25.x 整段排除**。所以 22.x / 23.x / 24.0~24.15 / 25.x 全部起不来。单独装 openclaw 且没显式给 `--node-major` 时，脚本会自动把 Node 抬到 24（目前最高 24.21.0，落在区间内）

## 国内网络的几个坑（脚本已处理）

**1. npm 官方源拉不动** → 走 npmmirror，失败自动切腾讯云、再切官方。

**2. Node 二进制不好下** → nvm 本体从 Gitee 镜像克隆；Node tarball 走 npmmirror。**注意 `latest-vN.x/` 目录列表是滞后的快照**：实测 npmmirror 的 `latest-v24.x/` 只列到 24.9.0，而 24.10.0 ~ 24.21.0 在 `vX.Y.Z/` 目录里都真实存在且可下（对照：`v24.99.99/` 与 `v23.99.0/` 都返回 404，确认那些 200 不是无脑返回）。所以脚本改为读 `index.json` 解析最高补丁版——那个文件是完整的（npmmirror 866 条、腾讯 863 条），nvm 自己读的也是它——再拼 `vX.Y.Z/` 的下载地址。只有镜像不提供 `index.json` 时才退回那份滞后列表，并明确告警。

**3. `npmmirror.com/mirrors/node/...` 是 302 跳转**，跟随跳转后抓不到可解析的文件列表。要抓列表得用 `https://registry.npmmirror.com/-/binary/node/...`。（`index.json` 同样是 302 跳 CDN，脚本的下载与探测都带 `-L`。）

**4. GitHub Releases 基本没法直连** → 所有工具都优先走 npm 包（平台二进制通过 npm optionalDependencies 下发），而不是从 GitHub 拉发布产物。openclaw 的 `dist/` 是自带的 bundle，`dist/` 里出现的 github.com 链接全是文档与 issue 引用，没有下载点。

## 装完还要做的事

脚本只解决**下载**问题，不解决**能不能用**问题。这些工具装完都需要自己配 API 地址和密钥，官方端点在国内通常直连不通：

| 工具 | 配置文件 |
|---|---|
| codex | `~/.codex/config.toml` |
| claude | `~/.claude/settings.json` |
| opencode | `~/.config/opencode/opencode.jsonc` |
| dsh | `~/.dsh/`（目录，存 profile 与会话） |
| openclaw | `~/.openclaw/`（目录，存 `openclaw.json`、`.env`、`agents/`、`workspace`、sqlite 状态） |

`bash install-ai-cli.sh doctor` 的「连通性」一栏会告诉你哪些端点通、哪些不通。

## dsh 怎么用

脚本只负责**装**，不负责跑。装完自己启动：

```bash
dsh web --host 127.0.0.1 --port 3080
```

- 它会在终端打印一个**带 token 的地址**，复制到浏览器打开
- **前台运行**，`Ctrl-C` 停止
- 想换端口就改 `--port`

另外两件事：

1. **要设 `DEEPSEEK_API_KEY`**，否则界面能打开但调不了模型。`doctor` 里会提示你有没有设。
2. **`--host 0.0.0.0` 不被支持**，dsh 会直接报错。只接受 `127.0.0.1` 或具体网卡地址。

> dsh 的版本控制、日志、开机自启等，本脚本都不管。`dsh -h` 和 `dsh web --help` 是上游自己的帮助。

## openclaw 怎么用

同样只负责**装**。装完先做一次配置，再起网关：

```bash
openclaw onboard     # 首次配置（模型、渠道等）
openclaw gateway     # 起网关，前台运行，Ctrl-C 停止
```

不想起服务、只想问一句：

```bash
openclaw agent --message "..."
```

排障用 `openclaw doctor` 和 `openclaw status`，`--help` / `--version` 是上游自己的帮助。

几点提醒：

1. **配置、agents、workspace、sqlite 状态都在 `~/.openclaw`**。脚本卸载时只摘 npm 包，不碰这个目录。
2. **它体积大**：tarball 约 72 MB，解包约 222 MB（`dist/` 下 6700 多个文件）。安装会比另外几个慢不少。
3. **Node 门槛怪**：`>=24.16.0 <25 || >=26.1.0`。25.x 被明确排除，24.x 要 `.16` 及以上。

## 已知限制

- **Claude Code 的 npm 路线已被官方弃用**（2026 年 1 月起）。包还能用，但不再自动更新，升级要重跑 `--upgrade`。想要 native 安装加 `--native`。
- **npm 12 默认拦截安装脚本**（`postinstall`）。codex / claude / opencode 依赖 `postinstall` 把平台二进制链接到 `bin/`，openclaw 的 `postinstall` 则负责裁剪 `dist/` 里的过期文件——被拦下都可能装出「能用但不完整」的状态。脚本目前**尚未处理**这一点——`--version` 对这类包不是可靠的体检项。npm 11.16～11.x 只有警告、脚本照跑，不受影响。
- **安装包后如果 PATH 上先命中旧版本**（例如系统包管理器装的），脚本会提示，但不会替你卸载它。
- **dsh 目前是开发者预览版**（npm 上是 `-rc` / `-alpha`），上游明确标注 developer preview，行为可能变。
- **探测 dsh 版本不能跑 `dsh --version`**：它是应用启动器，上游规定「启动器不认识的参数会被交给 profile」，直接跑有可能真去拉起一个 web profile 把预检挂住。脚本改为读已安装包的 `package.json`，只在读不到时才退回 `--version`（带 5 秒超时）。
- **dsh 的依赖树很大**（73 个生产依赖）。爬取时实测这些在国内镜像上零缺失，但安装会比 codex / claude / opencode 慢。
- **dsh 只走 npm 预编译包，不提供源码构建**。本脚本不 clone 仓库、不装 pnpm、不编译。要改 dsh 源码请自行 clone 上游。
- **openclaw 只走 npm 包**，不做源码构建（上游另有 `openclaw.ai/install.sh`，本脚本不用它）。
- **openclaw 装完不会自己跑起来**，且它是**网关/常驻服务**（Telegram、Discord、Slack、WhatsApp 等渠道 + 浏览器控制 + cron），不是敲完就结束的 CLI。脚本只管装。
- **openclaw 的传递依赖没有穷举验证过**。只逐版本核对了 66 个**直接**依赖在国内镜像上零缺失；npmmirror 是全量同步，风险低，但没证。
- **openclaw 的 `bin/` 与 `--version` 探测是可靠的**（上游文档明确 `--help` / `--version` 走 fast path），所以不像 dsh 那样需要读 `package.json` 绕开。

## 状态

- **Node 版本解析（v1.2.1）**：原先从 `latest-vN.x/` 目录列表挑最高补丁版，而那份列表在镜像上是滞后的——`--node-major 24` 会装成 24.9.0，而不是 24.21.0。已改为读 `index.json`。在 Git Bash 下真下载并解压过 24.21.0（`node_version.h` 确认为 24.21.0），降级路径也单独验过（模拟无 `index.json` 的镜像，确认告警并正确退回老布局）
- 在 Windows 的 Git Bash 下验证过：语法、`doctor`、`--dry-run`、`--uninstall`、非交互跳过、回答解析（`y/N/a/q`）
- 在 Linux 上实测过 npm 路线安装 opencode（npm 11.19.0 / Node v24.21.0）
- **dsh 部分**：`node_satisfies_dsh` 的 9 个版本用例（含必须被拒的 Node 23.x）、装/卸两条集成路径、以及「卸载不得触碰 `~/.dsh`」，都用假 node/npm + 沙箱 HOME 跑过
- **openclaw 部分（v1.3.0）**：`node_satisfies_openclaw` 的 13 个版本用例（含必须被拒的 25.x 和 24.15）、自动抬升 Node 的四种情形（单独装 / 显式 `--node-major 22` / 显式 26 / 装 dsh 时不误抬）、以及「卸载不得触碰 `~/.openclaw`」的沙箱实测。测试期间抓到并修掉一个真 bug：`27.0.0` 本应被 `>=26.1.0` 接受，原实现因写成「major ≥ 26 且 minor ≥ 1」而误拒
- **尚未在完整 Linux 环境跑通全部落盘路径**（`nvm install`、`tar -xJf`、各工具的 npm 安装）
- **dsh 的 npm 安装与 `dsh web` 启动尚未在真机跑过**。`@deepseek-ai/dsh` 的可装性是在 npm 元数据层面验证的（73 个生产依赖在国内镜像零缺失、平台二进制走 optionalDependencies 正常下发），但最终仍需真机确认一次
- **openclaw 的 npm 安装与 `openclaw gateway` 启动尚未在真机跑过**。同样只在 npm 元数据层面验证过（66 个直接依赖在国内镜像上精确版本零缺失、`dist/` 里的 GitHub 链接都是文档引用而非下载点），且 72 MB 的包实际下载解压仍需真机确认

## License

未指定。
