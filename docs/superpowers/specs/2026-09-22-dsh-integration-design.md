# 把 DeepSeek Harness (dsh) 整合进 install-ai-cli.sh — 设计文档

日期：2026-09-22
状态：已确认，待实现

## 1. 背景

`deploy.sh` 是一份 612 行的 DeepSeek Harness 部署脚本，管理 dsh 的完整生命周期（clone 源码 → pnpm 构建 → 补齐原生产物 → 后台常驻 → 停止/查看/重置）。

`install-ai-cli.sh` 是一份 859 行的国内网络 CLI 安装器，负责 codex / claude / opencode 三个 npm 全局包的安装。

目标是把 dsh 并进 `install-ai-cli.sh`，让后者成为唯一的 dsh 入口。

### 为什么不能直接合并

两者不是同一类东西：`install-ai-cli.sh` 装的是**一次性 CLI 二进制**，装完即结束、不写脚本所在目录、可在任意位置执行（含 `curl | bash`）；`deploy.sh` 是**带状态的服务管理器**，写 PID 文件、日志目录、端口，且所有状态路径都基于 `BASH_SOURCE` 解析出的脚本自身目录。

`ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` 在 `curl | bash` 场景下会退化——`BASH_SOURCE` 为空，`ROOT_DIR` 变成调用者当时的工作目录，导致"在哪个目录敲命令，日志和 pid 就落在哪儿"。这是整合中第一个必须解决的结构性冲突。

## 2. 关键决策

| 决策 | 选择 | 理由 |
|---|---|---|
| dsh 形态 | **只用预编译**（npm 包），不做源码构建 | 见 §3 |
| 生命周期 | **全量管理**：up / down / status / logs / verify / reset | 用户明确要求 |
| 命令形态 | **命名空间** `dsh <子命令>` | 现有动词表零改动，dsh 自成一组 |
| 安装方式 | **`npm i -g @deepseek-ai/dsh`**，非 `npx` | 见 §5 |
| 文件结构 | **单文件内联**，`dsh_` 前缀分区 | `curl \| bash` 无法 source 相对路径的库 |
| `all` 是否含 dsh | **不含** | 保持 `all` 语义不变，避免强制提升 Node 门槛 |
| deploy.sh | **先实现并验证通过、再删** | 出问题时保留可对照的参考实现 |
| 脚本状态目录 | **`DSH_RUN_DIR`**，非 `DSH_HOME` | 见 §4，`DSH_HOME` 是 dsh 自己的变量 |

## 3. 预编译方案可行性（全部经实测验证）

以下结论来自实际拉取 npm 元数据、tarball 与包内 README，非推断：

- `@deepseek-ai/dsh` 在 npmmirror 上存在，`latest = 0.1.5-rc.2`
- 包结构：`"bin": { "dsh": "lib/bin.js" }`
- **生产依赖 73 条，npmmirror 上零缺失**
- 该包共约 119 条依赖（73 生产 + 46 开发）。开发依赖中的 `@deepseek-ai/dsh-experimental-code-runtime-python` 在 npmmirror 和官方 npmjs.org 上**都不存在**（HTTP 404）。它是 **devDependency**，`npm i -g` 不安装开发依赖，**不影响安装**
- **原生产物由 npm 自动下发**：原生插件 `node-addon-require-builtin` 使用标准 optionalDependencies 平台包模式（`-linux-x64-gnu` / `-linux-arm64-gnu` / `-darwin-arm64` / `-win32-x64-msvc` …），npm 按 `os`/`cpu` 自动只装匹配的那一个。**不需要任何手工补齐**——这关闭了本设计最大的一个未知项
- **web profile 所需的组合包全部就位**：`dsh-base`、`dsh-web-app`、`dsh-headless`、`dsh-sdk-app`、`dsh-sdk-minimal`、`dsh-acp-app` 六个均在依赖列表且在镜像上
- 成熟度：`-rc` / `-alpha`，**开发者预览版**，需在文档中明确标注
- 平台限制：dsh 明确拒绝 `--host 0.0.0.0`，只接受 `127.0.0.1` 或具体网卡地址

> 过程教训一则：初查时用 `tr` 粗暴切分 package.json 统计依赖，把 devDependencies 算进了生产依赖，误报"国内装不上"。必须按缩进跟踪 JSON 块名做块级定位，才能得到可信结论。

## 4. 状态与路径

### `DSH_HOME` 是 dsh 自己的变量，不可占用

`@deepseek-ai/dsh-home-paths` 中定义：`DSH_HOME_ENV = "DSH_HOME"`、`DSH_HOME_DIR_NAME = ".dsh"`。dsh 用 `$DSH_HOME`（默认 `~/.dsh`）存放 profile、`cordis.patch.yml` 等**用户数据**。

脚本自己的运行态必须用另一个名字：

```
DSH_RUN_DIR="${DSH_RUN_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/install-ai-cli/dsh}"
├── dsh.log      # 服务日志，up / status / logs 都读它
├── dsh.pid      # 启动时记录的顶层 PID（辅助，非唯一依据）
└── dsh.env      # 可选覆盖：DSH_PORT / DSH_HOST / DSH_WAIT / DSH_WORKDIR
```

**`reset --purge` 绝不触碰 `$DSH_HOME`（`~/.dsh`）**。那里是用户的 profile 与会话数据，删掉等于毁数据。purge 只清理 `DSH_RUN_DIR` 下的日志与 pid 文件。这一点要在 `--purge` 的确认提示里写明。

### 不使用脚本所在目录

原因见 §1。预编译模式下**没有 checkout 目录**，因此 deploy.sh 中下列逻辑全部不需要移植（约 300 行）：

`resolve_pnpm`、`ensure_checkout`、`native_dir`、`native_required_paths`、`native_missing`、`ensure_native_prebuilt`、`verify_integrity`、`smoke_native`、`libc_variant`、`detect_platform`，以及 `cmd_install` 中 `pnpm install` / `pnpm run build` 的全部构建分支。

## 5. 命令面

```bash
bash install-ai-cli.sh dsh                 # 安装；已装则走现有询问流程（y/N/a/q）
bash install-ai-cli.sh dsh up              # 后台启动 → 等就绪 → 打印带 token 的地址
bash install-ai-cli.sh dsh status          # 进程 / 工作区 / 端口 / HTTP 码 / 访问地址
bash install-ai-cli.sh dsh logs            # tail -f
bash install-ai-cli.sh dsh down            # SIGTERM → 最多 10s → SIGKILL
bash install-ai-cli.sh dsh doctor          # dsh 专属体检
bash install-ai-cli.sh dsh verify          # 全链路：装→起→授权→停→再起
bash install-ai-cli.sh dsh reset [--purge] # 停 + 清运行态；--purge 删日志（不动 ~/.dsh）
```

`dsh up` 接受 `--port` / `--host` / `--wait`。

### 为什么用 `npm i -g` 而不是 deploy.sh 原本的 `npx --yes`

deploy.sh 选 npx 是因为它服务于源码构建主路径，预编译只是搭车。作为独立工具融入时 npx 的代价全部暴露：

- 预检看不见它（没有已安装状态可查）
- `--uninstall` 卸不掉它（不在 npm 全局树里）
- 每次 `dsh up` 都要重新解析依赖树，73 个包在国内网络下是几十秒的抖动

走 `npm i -g` 则直接复用现有的预检、卸载、`--upgrade` 整套逻辑。

## 6. 工作区目录（易错点）

上游 README 明确：**"The invoking directory is the default workspace root."**

因此启动时**必须在调用者当时所在的目录**，绝不能 `cd` 到状态目录再启动。deploy.sh 的预编译分支写的是 `cwd="$ROOT_DIR"`（即脚本目录），照搬到本脚本后会让每次 dsh 会话的工作区根目录变成 `~/.local/state/.../dsh`——用户的项目目录完全不会被看到。

实现要求：

- `dsh up` 记录调用时的 `$PWD` 到 `DSH_WORKDIR`，并在该目录下启动
- `dsh status` 通过 `readlink /proc/$pid/cwd` 回报当前工作区根目录，让用户确认没跑错地方
- `dsh doctor` 提示工作区根目录的来源

## 7. 组件划分

单文件内联，但严格分区，函数一律 `dsh_` 前缀。

**复用既有基础设施**（不重复实现）：
`log` / `ok` / `warn` / `err` / `step` 日志族、`run()`、`ask()` / `detect_prompt_capability()`、registry 三级回退、`ensure_node` / `node_via_nvm` / `node_via_tarball`、`ensure_npm_prefix`、`tool_install_kind`、`decide_existing`、`install_tool`、`uninstall_tool`、`preflight`

**不移植**：deploy.sh 的 `step` / `warn` / `die` / `ok` 日志函数——与现有同名不同格式，直接搬会在同一脚本内造成两套输出风格。

**新增（dsh 特有）**：
`dsh_run_dir` / `dsh_env_load` / `dsh_matching_pids` / `dsh_running_pid` / `dsh_http_code` / `dsh_port_listening` / `dsh_is_ready_code` / `dsh_access_url` / `dsh_wait_ready` / `dsh_verify_web_access` / `dsh_cmd_*`

## 8. 进程匹配

**不照搬** deploy.sh 的 `pgrep -f "(dsh web|bin\.ts web) --host $HOST --port $PORT"`。

该模式要求命令行中出现**连续的** `dsh web` 子串。源码模式下进程是 `pnpm dsh web …`，能命中；但预编译模式下 bin 为 `lib/bin.js`，实际命令行可能是 `node …/dsh/lib/bin.js web …` 或 `node …/.bin/dsh web …`，取决于 shim 的 spawn 方式，**匹配结果不可靠**。

改为两级判定：

1. 读 `dsh.pid`，若该 PID 存活**且** `/proc/$pid/cmdline` 含 `--port $PORT` → 采用
2. 否则扫 `pgrep -f -- "--port $PORT"`，逐个读 `/proc/$pid/cmdline`，要求**同时**含 `dsh` 与 `--port $PORT` 才认

`npm i -g` 后命令行形如 `node ~/.npm-global/lib/node_modules/@deepseek-ai/dsh/lib/bin.js web --host … --port 3080`，含 `dsh` 且含 `--port`，两级均可命中。联合 `--port` 条件用于防止误杀机器上其他 node 服务。

## 9. 探测与授权

以下逻辑在 deploy.sh 中是正确设计，予以保留：

**就绪判定**：HTTP `2xx` / `3xx` / `401` 均算就绪（401 = 服务活着但需要凭据）。启动后给 15s 宽限期等待进程出现（shim 需要 fork+exec，进程表瞬时可能看不到），就绪上限 300s。**超时或进程中途消失时，一律先输出日志尾部 30 行再报错。**

**访问地址**：从日志中提取 `dsh web: http://…`，把带一次性 token 的完整 URL 打印给用户。

**授权验证**（`verify` 使用）：裸访问拿 401 → 用 `?token=` 换授权 cookie（期望 303）→ 带 cookie 打开 UI（期望 2xx）。三层缺一不可——只看裸访问会把"就绪但需凭据"误判为失败，只看 token 那步会把 303 误判为未通过。

## 10. Node 门槛

dsh 要求 `^22.19.0 || >=24.0.0`，严于现有的"≥22"。

现有 `_pick_latest_node` 已会选择该大版本的最大补丁（v22 → 22.20.0），因此**本脚本安装的 Node 天然满足**。

唯一会卡住的情况：机器上已存在自装的 Node 22.x 且 minor < 19（如 22.3.0）。此时明确提示并升级，不静默放行。

`all` 不含 dsh，因此 `all` 的 Node 门槛维持现状，不因此变更。

## 11. 错误处理

- 启动失败必须输出日志尾部，不吞错
- `down` 走 SIGTERM → 最多 10s → SIGKILL
- `up` 时若检测到已运行，提示先 `down`，不静默重启
- 端口被占用时明确报错并提示换 `--port`
- `dsh doctor` 与 `dsh up` 输出中明确标注「开发者预览版（-rc）」
- `--host 0.0.0.0` 拒绝并说明 dsh 不支持
- `reset --purge` 的确认提示必须写明只删运行态日志、不动 `~/.dsh`

## 12. 测试策略

**可在 Windows Git Bash 验证**：语法（`bash -n`）、`doctor`、`--dry-run`、参数解析、非交互跳过、命令分发

**无法在 Windows 验证**：`/proc/$pid/cmdline`、`/proc/$pid/cwd`、`pgrep`、`setsid`、`ss`、真实的 `nohup` 后台化——这些在 Git Bash 下要么不存在要么语义不同

**必须在真实 Linux 完成**：`dsh up → status → verify → down` 全链路，并确认 `status` 报告的工作区根目录是预期目录而非状态目录。

在完成这一步之前，README 的「状态」章节必须如实写明未验证，不得写成已完成。

## 13. README 更新

- 命令表新增 dsh 一组
- 新增说明：dsh 是什么、开发者预览版、需要 `DEEPSEEK_API_KEY`、默认端口 3080、运行态目录位置、如何停止、工作区根目录取决于执行 `dsh up` 时所在目录
- 明确 `~/.dsh` 是 dsh 自己的数据目录，脚本不碰
- 「已知限制」新增：`-rc` 版本、依赖树 73 个包、不支持 `--host 0.0.0.0`

## 14. 交付顺序

1. 在 `install-ai-cli.sh` 中实现 dsh 安装 + 生命周期
2. 更新 README
3. 在真实 Linux 上完整验证 `dsh up → status → verify → down`
4. 验证通过后删除 `deploy.sh`（`git rm`；git 历史中仍可找回）

deploy.sh 必须**最后**删除，不是最先。
