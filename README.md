# install-ai-cli

国内网络下 Linux 一键安装 **Codex CLI** / **Claude Code** / **opencode**。

一个不带依赖的 bash 脚本，把国内环境装这三个 CLI 时会撞上的坑一次性填掉：Node 版本不够、npm 拉不动、平台二进制下发失败、GitHub 直连被重置。

## 特性

- **预检优先**：先列出三个工具的安装现状，已安装的**不会直接覆盖**，而是逐个询问「是否卸载并重新安装？」（`y` / `N` / `a` / `q`）
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
| `all` | 三个全装 |
| `doctor` | 体检：系统、Node/npm、三个工具状态、网络连通性 |
| `version` | 打印脚本版本 |
| `help` | 帮助 |

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

## 国内网络的几个坑（脚本已处理）

**1. npm 官方源拉不动** → 走 npmmirror，失败自动切腾讯云、再切官方。

**2. Node 二进制不好下** → nvm 本体从 Gitee 镜像克隆；Node tarball 走 npmmirror。npmmirror 的 `latest-vN.x/` 目录里装的是该大版本的**全部**补丁版（实测 v22 下有 44 个文件，22.0.0 到 22.20.0），所以必须比出版本号最大的那个，不能取第一个匹配。

**3. `npmmirror.com/mirrors/node/...` 是 302 跳转**，跟随跳转后抓不到可解析的文件列表。要抓列表得用 `https://registry.npmmirror.com/-/binary/node/...`。

**4. GitHub Releases 基本没法直连** → 三个工具都优先走 npm 包（平台二进制通过 npm optionalDependencies 下发），而不是从 GitHub 拉发布产物。

## 装完还要做的事

脚本只解决**下载**问题，不解决**能不能用**问题。三个工具装完都需要自己配 API 地址和密钥，官方端点在国内通常直连不通：

| 工具 | 配置文件 |
|---|---|
| codex | `~/.codex/config.toml` |
| claude | `~/.claude/settings.json` |
| opencode | `~/.config/opencode/opencode.jsonc` |

`bash install-ai-cli.sh doctor` 的「连通性」一栏会告诉你哪些端点通、哪些不通。

## 已知限制

- **Claude Code 的 npm 路线已被官方弃用**（2026 年 1 月起）。包还能用，但不再自动更新，升级要重跑 `--upgrade`。想要 native 安装加 `--native`。
- **npm 12 默认拦截安装脚本**（`postinstall`）。这三个包都依赖 `postinstall` 把平台二进制链接到 `bin/`，届时可能会装出可执行但不完整的壳。脚本目前**尚未处理**这一点——`--version` 对这类「壳 + 平台二进制」的包不是可靠的体检项。npm 11.16～11.x 只有警告、脚本照跑，不受影响。
- **安装包后如果 PATH 上先命中旧版本**（例如系统包管理器装的），脚本会提示，但不会替你卸载它。

## 状态

- 在 Windows 的 Git Bash 下验证过：语法、`doctor`、`--dry-run`、`--uninstall`、非交互跳过、回答解析（`y/N/a/q`）
- 在 Linux 上实测过 npm 路线安装 opencode（npm 11.19.0 / Node v24.21.0）
- **尚未在完整 Linux 环境跑通全部落盘路径**（`nvm install`、`tar -xJf`、三个工具的 npm 安装）

## License

未指定。
