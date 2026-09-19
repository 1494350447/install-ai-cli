#!/usr/bin/env bash
#
# install-ai-cli.sh — 国内网络 Linux 一键安装 Codex / Claude Code / opencode
#
#   bash install-ai-cli.sh codex
#   bash install-ai-cli.sh all
#   bash install-ai-cli.sh doctor
#
# 远程一条命令：
#   curl -fsSL https://your.host/install-ai-cli.sh | bash -s -- all
#
# 设计原则：
#   1. 先预检，已安装的不直接覆盖 —— 会问你要不要卸载重装
#   2. 不修改你的全局 npm registry，只在安装时用 --registry 临时指定
#   3. 尽量不用 sudo；全局安装一律走用户目录，避免 root 归属的坑
#   4. 幂等，可重复执行
#

# ---------------------------------------------------------------- 前置：确保 bash
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  echo "此脚本需要 bash。请先安装：Debian/Ubuntu: apt install bash | Alpine: apk add bash" >&2
  exit 1
fi

set -euo pipefail

SCRIPT_VERSION="1.1.0"

# ---------------------------------------------------------------- 默认参数
NODE_MAJOR="22"
NODE_MIRROR="https://registry.npmmirror.com/-/binary/node"
REGISTRY="https://registry.npmmirror.com"
REGISTRY_FALLBACKS="https://mirrors.cloud.tencent.com/npm/ https://registry.npmjs.org"
FORCE=0
YES=0
DRY_RUN=0
VERBOSE=0
SKIP_NODE=0
USE_NATIVE=0
SET_REGISTRY=0
DO_UNINSTALL=0
REINSTALL_ALL=0
CAN_PROMPT=0
ASK_ANSWER=""
PROXY=""
CMD=""
TOOLS=""

# ---------------------------------------------------------------- 输出
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RST=$'\033[0m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'
  C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_BLU=$'\033[36m'
else
  C_RST=""; C_DIM=""; C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""
fi

log()  { printf '%s==>%s %s\n' "$C_BLU" "$C_RST" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn() { printf '%swarn%s %s\n' "$C_YEL" "$C_RST" "$*" >&2; }
err()  { printf '%serr %s %s\n' "$C_RED" "$C_RST" "$*" >&2; }
die()  { err "$*"; exit 1; }
step() { printf '\n%s── %s ──%s\n' "$C_DIM" "$*" "$C_RST"; }

run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '%s[dry-run]%s %s\n' "$C_DIM" "$C_RST" "$*"
    return 0
  fi
  if [ "$VERBOSE" = 1 ]; then
    printf '%s[exec]%s %s\n' "$C_DIM" "$C_RST" "$*"
  fi
  "$@"
}

TMPDIRS=()
cleanup() { [ ${#TMPDIRS[@]} -gt 0 ] && rm -rf "${TMPDIRS[@]}" 2>/dev/null || true; }
trap cleanup EXIT

mktmp() { local d; d="$(mktemp -d)"; TMPDIRS+=("$d"); printf '%s' "$d"; }

# ---------------------------------------------------------------- 交互
# 注意：`curl | bash` 时 stdin 就是脚本本身，必须从 /dev/tty 读，
# 否则 read 会把后面的脚本文本当回答吃掉。
detect_prompt_capability() {
  CAN_PROMPT=0
  if [ -t 0 ] && [ -t 1 ]; then
    CAN_PROMPT=1
  elif ( : < /dev/tty ) 2>/dev/null; then
    # [ -r /dev/tty ] 不够：设备节点存在 ≠ 能打开（没有控制终端时会 ENXIO）
    CAN_PROMPT=1
  fi
}

# 提问，回答写入全局 ASK_ANSWER；返回非 0 表示问不了
ask() {
  ASK_ANSWER=""
  [ "$CAN_PROMPT" = 1 ] || return 1
  printf '%s' "$1" >&2
  if [ -r /dev/tty ]; then
    read -r ASK_ANSWER < /dev/tty || ASK_ANSWER=""
  else
    read -r ASK_ANSWER || ASK_ANSWER=""
  fi
  return 0
}

# ---------------------------------------------------------------- 用法
usage() {
  cat <<'EOF'
国内网络 Linux 一键安装 Codex / Claude Code / opencode

用法:
  bash install-ai-cli.sh <命令> [选项]

命令:
  codex                安装 OpenAI Codex CLI
  claude               安装 Claude Code
  opencode             安装 opencode
  all                  三个全装
  doctor               体检：打印环境、版本、路径、连通性
  version              打印脚本版本
  help                 显示本帮助

已安装的工具不会被直接覆盖：
  脚本先做一次预检，把三个工具的安装状态列出来，然后对每个已安装的
  工具单独询问「是否卸载并重新安装」。可回答 y / N / a / q。

选项:
      --reinstall          跳过询问，已装的一律卸载重装（同 --upgrade）
  -f, --force, --upgrade   同 --reinstall
  -y, --yes                非交互：已安装的一律跳过，不重装
      --uninstall          卸载指定工具（配合 codex/claude/opencode/all）
      --registry <URL>     npm 源，默认 https://registry.npmmirror.com
      --node-mirror <URL>  Node 二进制源，默认 https://registry.npmmirror.com/-/binary/node
      --node-major <N>     Node 大版本，默认 22
      --no-node            跳过 Node 的安装/升级（假定已就绪）
      --native             Claude Code 用官方 curl 安装器（默认走 npm，国内更稳）
      --set-registry       永久把 npm 全局源设为 --registry 指定的地址
                           （默认不改动你的全局配置）
      --proxy <URL>        走代理，如 http://127.0.0.1:7897
  -n, --dry-run            只打印将执行的命令，不实际改动
  -v, --verbose            打印每条执行的命令
  -h, --help               显示本帮助

示例:
  bash install-ai-cli.sh all                 # 预检后逐个询问
  bash install-ai-cli.sh codex --reinstall   # 直接重装，不问
  bash install-ai-cli.sh all -y              # 非交互，已装的跳过
  bash install-ai-cli.sh doctor
EOF
}

# ---------------------------------------------------------------- 参数解析
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      codex|claude|opencode|all|doctor|version|help) CMD="$1" ;;
      -h|--help)            CMD="help" ;;
      -f|--force|--upgrade|--reinstall) FORCE=1 ;;
      -y|--yes)             YES=1 ;;
      --uninstall)          DO_UNINSTALL=1 ;;
      --registry)           REGISTRY="${2:?--registry 需要一个 URL}"; shift ;;
      --node-mirror)        NODE_MIRROR="${2:?--node-mirror 需要一个 URL}"; shift ;;
      --node-major)         NODE_MAJOR="${2:?--node-major 需要一个数字}"; shift ;;
      --no-node)            SKIP_NODE=1 ;;
      --native)             USE_NATIVE=1 ;;
      --set-registry)       SET_REGISTRY=1 ;;
      --proxy)              PROXY="${2:?--proxy 需要一个 URL}"; shift ;;
      -n|--dry-run)         DRY_RUN=1 ;;
      -v|--verbose)         VERBOSE=1 ;;
      *)                    die "未知参数：$1（用 --help 查看用法）" ;;
    esac
    shift
  done

  [ -n "$CMD" ] || { usage; exit 1; }
}

apply_proxy() {
  [ -n "$PROXY" ] || return 0
  export http_proxy="$PROXY" https_proxy="$PROXY" HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY"
  export no_proxy="localhost,127.0.0.1,::1" NO_PROXY="$no_proxy"
  log "已启用代理 $PROXY"
}

# ---------------------------------------------------------------- 系统探测
SUDO=""
PM=""

detect_env() {
  local m
  if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
  elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    SUDO=""
  fi

  for m in apt-get dnf yum pacman apk zypper; do
    if command -v "$m" >/dev/null 2>&1; then PM="$m"; break; fi
  done
}

detect_node_arch() {
  case "$(uname -m)" in
    x86_64|amd64)  echo "x64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv6l) echo "armv7l" ;;
    ppc64le)       echo "ppc64le" ;;
    s390x)         echo "s390x" ;;
    loongarch64|loong64)
      die "Node 官方没有 LoongArch 的 Linux 构建。请先用系统包管理器安装 Node >= ${NODE_MAJOR}，再带 --no-node 重跑本脚本。" ;;
    *) die "未知 CPU 架构：$(uname -m)" ;;
  esac
}

# ---------------------------------------------------------------- 网络工具
fetch_stdout() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 15 --retry 2 "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- --timeout=15 --tries=2 "$1"
  else
    return 1
  fi
}

fetch_file() {
  if command -v curl >/dev/null 2>&1; then
    curl -fL --connect-timeout 15 --retry 2 -o "$2" "$1"
  else
    wget -q --timeout=15 --tries=2 -O "$2" "$1"
  fi
}

probe_url() {
  local url="$1" code
  command -v curl >/dev/null 2>&1 || { printf 'n/a'; return 0; }
  code="$(curl -fsS --connect-timeout 6 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || true)"
  if [ -z "$code" ] || [ "$code" = "000" ]; then
    printf 'FAIL'
  else
    printf '%s' "$code"
  fi
}

# ---------------------------------------------------------------- 系统依赖
# shellcheck disable=SC2086
_pm_install_cmd() {
  case "$PM" in
    apt-get) $SUDO apt-get update -qq && $SUDO apt-get install -y --no-install-recommends "$@" ;;
    dnf)     $SUDO dnf install -y "$@" ;;
    yum)     $SUDO yum install -y "$@" ;;
    pacman)  $SUDO pacman -Sy --noconfirm --needed "$@" ;;
    apk)     $SUDO apk add --no-cache "$@" ;;
    zypper)  $SUDO zypper --non-interactive install "$@" ;;
    *)       return 1 ;;
  esac
}

install_system_pkg() {
  [ -n "$PM" ] || { warn "未识别包管理器，请手动安装：$*"; return 1; }
  if [ "$(id -u)" -ne 0 ] && [ -z "$SUDO" ]; then
    warn "安装 $* 需要 root，但当前用户无 sudo，跳过"; return 1
  fi
  log "通过 $PM 安装系统依赖：$*"
  run _pm_install_cmd "$@"
}

ensure_base_deps() {
  if command -v curl >/dev/null 2>&1 && command -v xz >/dev/null 2>&1; then
    return 0
  fi
  case "$PM" in
    apt-get) install_system_pkg ca-certificates curl xz-utils tar git || true ;;
    apk)     install_system_pkg ca-certificates curl xz tar git bash || true ;;
    *)       install_system_pkg ca-certificates curl xz tar git || true ;;
  esac
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    die "curl 和 wget 都不可用，无法继续。请手动安装其一后重试。"
  fi
}

ensure_git() {
  command -v git >/dev/null 2>&1 && return 0
  install_system_pkg git || return 1
  command -v git >/dev/null 2>&1
}

# ---------------------------------------------------------------- PATH 持久化
add_path_rc() {
  local line="$1" rc wrote=0
  if [ "$DRY_RUN" = 1 ]; then
    printf '%s[dry-run]%s 追加到 shell rc：%s\n' "$C_DIM" "$C_RST" "$line"
    return 0
  fi
  for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    [ -e "$rc" ] || continue
    if grep -qxF "$line" "$rc" 2>/dev/null; then wrote=1; continue; fi
    printf '\n# added by install-ai-cli.sh\n%s\n' "$line" >> "$rc"
    wrote=1
  done
  [ "$wrote" = 1 ] || printf '\n# added by install-ai-cli.sh\n%s\n' "$line" >> "$HOME/.bashrc"
}

# ---------------------------------------------------------------- Node
node_major_installed() {
  command -v node >/dev/null 2>&1 || return 1
  command -v npm  >/dev/null 2>&1 || return 1
  local v
  v="$(node -v 2>/dev/null || true)"
  v="${v#v}"; v="${v%%.*}"
  [ -n "$v" ] && [ "$v" -ge "$NODE_MAJOR" ] 2>/dev/null
}

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

node_via_nvm() {
  export NVM_DIR
  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    ensure_git || return 1
    if [ -e "$NVM_DIR" ]; then
      warn "$NVM_DIR 已存在但没有 nvm.sh，不覆盖，直接尝试加载"
    else
      log "从 Gitee 镜像克隆 nvm 到 $NVM_DIR"
      run git clone --depth=1 https://gitee.com/mirrors/nvm.git "$NVM_DIR" || return 1
    fi
  fi

  log "通过 nvm 安装 Node ${NODE_MAJOR}（二进制源 $NODE_MIRROR）"
  export NVM_NODEJS_ORG_MIRROR="$NODE_MIRROR"
  set +u
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh" || { set -u; return 1; }
  nvm install "$NODE_MAJOR" || { set -u; return 1; }
  nvm alias default "$NODE_MAJOR" >/dev/null 2>&1 || true
  nvm use default >/dev/null 2>&1 || true
  set -u

  add_path_rc "export NVM_DIR=\"$NVM_DIR\""
  add_path_rc "[ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\""
  node_major_installed
}

# $1 > $2 ？纯 bash 比较，不依赖 sort -V（busybox 没有）
_node_version_gt() {
  local IFS=.
  # shellcheck disable=SC2206
  local -a a=($1) b=($2)
  local i x y
  for i in 0 1 2; do
    x="${a[i]:-0}"; y="${b[i]:-0}"
    [ "$x" -gt "$y" ] 2>/dev/null && return 0
    [ "$x" -lt "$y" ] 2>/dev/null && return 1
  done
  return 1
}

# latest-vN.x 目录里装的是该大版本的【全部】补丁版，必须比出版本号最大的那个
_pick_latest_node() {
  local f v best="" best_v=""
  for f in $1; do
    v="${f#node-v}"; v="${v%-linux-*}"
    if [ -z "$best_v" ] || _node_version_gt "$v" "$best_v"; then
      best_v="$v"; best="$f"
    fi
  done
  [ -n "$best" ] && printf '%s' "$best"
  return 0
}

node_via_tarball() {
  local arch dest base list matches fname url tmp extracted=0
  arch="$(detect_node_arch)"
  dest="${NODE_HOME:-$HOME/.local/node}"
  tmp="$(mktmp)"

  for base in \
    "${NODE_MIRROR}" \
    "https://registry.npmmirror.com/-/binary/node" \
    "https://mirrors.cloud.tencent.com/nodejs-release"
  do
    log "从 $base 解析最新的 Node v${NODE_MAJOR}.x（linux-${arch}）"
    list="$(fetch_stdout "$base/latest-v${NODE_MAJOR}.x/")" || continue

    matches="$(printf '%s\n' "$list" | grep -oE "node-v${NODE_MAJOR}\.[0-9]+\.[0-9]+-linux-${arch}\.tar\.xz" || true)"
    fname="$(_pick_latest_node "$matches")"
    [ -n "$fname" ] || { warn "该源下没找到 linux-${arch} 的 Node v${NODE_MAJOR} 包"; continue; }
    log "选中 $fname"

    url="$base/latest-v${NODE_MAJOR}.x/$fname"
    log "下载 $fname"
    fetch_file "$url" "$tmp/$fname" || { warn "下载失败：$url"; continue; }

    run mkdir -p "$dest"
    if run tar -xJf "$tmp/$fname" -C "$dest" --strip-components=1; then
      extracted=1; break
    fi
    warn "解压失败：$fname"
  done

  [ "$extracted" = 1 ] || return 1

  export PATH="$dest/bin:$PATH"
  add_path_rc "export PATH=\"${dest}/bin:\$PATH\""
  ok "Node 已解压到 $dest"
  node_major_installed
}

ensure_node() {
  if [ "$SKIP_NODE" = 1 ]; then
    node_major_installed || warn "已指定 --no-node，但当前 Node 不满足 >= ${NODE_MAJOR}，后续 npm 安装可能失败"
    return 0
  fi

  if node_major_installed; then
    ok "Node 已就绪：$(node -v)  ($(command -v node))"
    return 0
  fi

  step "安装 Node.js ${NODE_MAJOR}+"
  if [ "$DRY_RUN" = 1 ]; then
    printf '%s[dry-run]%s 将通过 nvm 或 npmmirror tarball 安装 Node %s\n' "$C_DIM" "$C_RST" "$NODE_MAJOR"
    return 0
  fi

  if node_via_nvm; then
    ok "Node 已就绪（nvm）：$(node -v)"
    return 0
  fi
  warn "nvm 路线失败，改用官方 tarball 直装"

  if node_via_tarball; then
    ok "Node 已就绪（tarball）：$(node -v)"
    return 0
  fi

  die "Node ${NODE_MAJOR}+ 自动安装失败。请手动安装后再带 --no-node 重跑本脚本。"
}

# ---------------------------------------------------------------- npm 全局目录
npm_global_writable() {
  local root d
  root="$(npm root -g 2>/dev/null || true)"
  [ -n "$root" ] || return 1
  d="$root"
  while [ ! -d "$d" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done
  [ -w "$d" ]
}

NPM_PREFIX=""
NPM_BIN_DIR=""

ensure_npm_prefix() {
  local prefix
  prefix="$(npm config get prefix 2>/dev/null || true)"

  if [ -n "$prefix" ] && npm_global_writable; then
    NPM_PREFIX="$prefix"
  else
    NPM_PREFIX="$HOME/.npm-global"
    log "默认全局目录不可写，改用 $NPM_PREFIX"
    run mkdir -p "$NPM_PREFIX"
    run npm config set prefix "$NPM_PREFIX" >/dev/null
  fi

  NPM_BIN_DIR="$NPM_PREFIX/bin"
  export PATH="$NPM_BIN_DIR:$PATH"
  add_path_rc "export PATH=\"${NPM_BIN_DIR}:\$PATH\""
}

apply_registry() {
  if [ "$SET_REGISTRY" = 1 ]; then
    log "按要求永久设置 npm 全局源为 $REGISTRY"
    run npm config set registry "$REGISTRY"
  fi
}

# ---------------------------------------------------------------- 工具元数据
tool_pkg() {
  case "$1" in
    codex)    echo "@openai/codex" ;;
    claude)   echo "@anthropic-ai/claude-code" ;;
    opencode) echo "opencode-ai" ;;
    *) return 1 ;;
  esac
}

tool_bin() {
  case "$1" in
    codex|claude|opencode) echo "$1" ;;
    *) return 1 ;;
  esac
}

tool_config_path() {
  case "$1" in
    codex)    echo "$HOME/.codex/config.toml" ;;
    claude)   echo "$HOME/.claude/settings.json" ;;
    opencode) echo "$HOME/.config/opencode/opencode.jsonc" ;;
  esac
}

tool_resolve() {
  local bin; bin="$(tool_bin "$1")"
  if command -v "$bin" >/dev/null 2>&1; then
    command -v "$bin"; return 0
  fi
  if [ -n "$NPM_BIN_DIR" ] && [ -x "$NPM_BIN_DIR/$bin" ]; then
    echo "$NPM_BIN_DIR/$bin"; return 0
  fi
  # 预检跑在 ensure_npm_prefix 之前时 NPM_BIN_DIR 还是空的，补一条本脚本的约定路径
  if [ -x "$HOME/.npm-global/bin/$bin" ]; then
    echo "$HOME/.npm-global/bin/$bin"; return 0
  fi
  if [ -x "$HOME/.local/bin/$bin" ]; then
    echo "$HOME/.local/bin/$bin"; return 0
  fi
  if [ -x "$HOME/.opencode/bin/$bin" ]; then
    echo "$HOME/.opencode/bin/$bin"; return 0
  fi
  return 1
}

tool_version() {
  local p out
  p="$(tool_resolve "$1")" || return 1
  out="$("$p" --version 2>/dev/null || true)"
  [ -n "$out" ] || return 1
  printf '%s\n' "${out%%$'\n'*}"
}

# npm 装的、官方安装器落的、还是 winget/brew/apt 之类别的来源
tool_install_kind() {
  local p dir
  p="$(tool_resolve "$1")" || { printf 'unknown'; return 0; }

  if [ "$p" = "$HOME/.local/bin/claude" ] || [ "$p" = "$HOME/.opencode/bin/opencode" ]; then
    printf 'native'; return 0
  fi

  # npm 全局布局：<prefix>/bin/x 旁边有 <prefix>/lib/node_modules
  dir="$(dirname "$p")"
  if [ -d "$dir/../lib/node_modules" ]; then
    printf 'npm'; return 0
  fi

  printf 'other'
}

kind_label() {
  case "$1" in
    native) echo "官方安装器" ;;
    npm)    echo "npm" ;;
    other)  echo "其他来源" ;;
    *)      echo "未知来源" ;;
  esac
}

# 只删我们自己装下去的明确路径，删什么都会打日志
remove_path() {
  local path="$1" desc="$2"
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    return 0
  fi
  log "删除${desc}：$path"
  run rm -rf -- "$path"
}

# ---------------------------------------------------------------- 安装
install_from_npm() {
  local pkg="$1" reg rl
  rl="$REGISTRY"
  if [ -n "$REGISTRY_FALLBACKS" ]; then
    rl="$REGISTRY $REGISTRY_FALLBACKS"
  fi

  # shellcheck disable=SC2086
  for reg in $rl; do
    log "npm install -g $pkg  （源 $reg）"
    if run npm install -g "$pkg" --registry="$reg" --no-fund --no-audit; then
      return 0
    fi
    warn "用 $reg 安装失败，换下一个源重试"
  done
  return 1
}

install_claude_native() {
  log "使用官方安装器（国内可能失败，失败会自动回退 npm）"
  if [ "$DRY_RUN" = 1 ]; then
    printf '%s[dry-run]%s curl -fsSL https://claude.ai/install.sh | bash\n' "$C_DIM" "$C_RST"
    return 0
  fi
  if curl -fsSL --connect-timeout 20 https://claude.ai/install.sh | bash; then
    hash -r 2>/dev/null || true
    tool_version claude >/dev/null 2>&1 && return 0
  fi
  warn "官方安装器未成功，回退到 npm 路线"
  return 1
}

# 已安装时决定怎么办 → reinstall | reinstall_all | skip | quit
# 注意：本函数在 $( ) 里跑（子 shell），不能在这里改 REINSTALL_ALL，
# 所以 a 只返回 reinstall_all，由调用方在父 shell 里置位。
decide_existing() {
  local t="$1" tv="$2" kind="$3"

  if [ "$FORCE" = 1 ] || [ "$REINSTALL_ALL" = 1 ]; then
    printf 'reinstall'; return 0
  fi

  if [ "$YES" = 1 ]; then
    printf 'skip'; return 0
  fi

  if [ "$CAN_PROMPT" != 1 ]; then
    warn "非交互环境，$t 已安装 → 跳过（要重装请加 --upgrade）"
    printf 'skip'; return 0
  fi

  if ! ask "$(printf '\n%s 已安装：%s（%s）\n  是否卸载并重新安装？\n    [y] 卸载并重装    [N] 跳过    [a] 其余已装的也一并重装    [q] 退出\n  请选择 [y/N/a/q] > ' "$t" "$tv" "$(kind_label "$kind")")"; then
    printf 'skip'; return 0
  fi

  case "$ASK_ANSWER" in
    y|Y|yes|YES)   printf 'reinstall' ;;
    a|A|all|ALL)   printf 'reinstall_all' ;;
    q|Q|quit|QUIT) printf 'quit' ;;
    *)             printf 'skip' ;;
  esac
}

install_tool() {
  local t="$1" pkg tv kind use_native decision resolved expected
  pkg="$(tool_pkg "$t")"
  use_native="$USE_NATIVE"

  step "安装 $t"

  if tv="$(tool_version "$t")"; then
    kind="$(tool_install_kind "$t")"
    decision="$(decide_existing "$t" "$tv" "$kind")"

    case "$decision" in
      reinstall|reinstall_all)
        if [ "$decision" = "reinstall_all" ]; then
          REINSTALL_ALL=1
          log "已选择：其余已安装的工具也一并重装"
        fi
        log "按要求先卸载已有安装"
        uninstall_tool "$t"
        if [ "$t" = claude ] && [ "$kind" = native ]; then
          use_native=1
        fi
        ;;
      quit)
        printf '\n%s已退出，未做任何改动。%s\n' "$C_YEL" "$C_RST"
        exit 0
        ;;
      *)
        ok "$t 已安装（$tv），保持不动。要重装请加 --upgrade"
        return 0
        ;;
    esac
  fi

  if [ "$t" = claude ] && [ "$use_native" = 1 ]; then
    if install_claude_native; then
      ok "claude 安装成功（native）：$(tool_version claude)"
      return 0
    fi
  fi

  install_from_npm "$pkg" || die "$t 安装失败（所有源都试过了）"

  if [ "$DRY_RUN" = 1 ]; then
    return 0
  fi

  hash -r 2>/dev/null || true
  if tv="$(tool_version "$t")"; then
    resolved="$(tool_resolve "$t")"
    expected="$NPM_BIN_DIR/$(tool_bin "$t")"
    if [ -n "$NPM_BIN_DIR" ] && [ "$resolved" != "$expected" ]; then
      warn "$t 已装到 $expected，但 PATH 上先命中的是 $resolved（$tv）"
      warn "旧版本仍在生效：请用原来的方式卸载它，或重开终端后再试"
    else
      ok "$t 安装成功：$tv"
      printf '     路径：%s\n' "$resolved"
    fi
  else
    warn "$pkg 已装但 $(tool_bin "$t") 无法执行。若是平台二进制没下发成功，请挂代理重试。"
    return 1
  fi
}

uninstall_tool() {
  local t="$1" pkg
  pkg="$(tool_pkg "$t")"
  step "卸载 $t"

  # 1) npm 装的
  if command -v npm >/dev/null 2>&1; then
    if run npm uninstall -g "$pkg" 2>/dev/null; then
      [ "$DRY_RUN" = 1 ] || ok "$pkg 已通过 npm 卸载"
    fi
  else
    warn "没有 npm，跳过 npm 卸载"
  fi

  # 2) 官方安装器落在别处的二进制
  case "$t" in
    claude)
      remove_path "$HOME/.local/bin/claude" "claude 启动器"
      remove_path "$HOME/.local/share/claude" "claude 程序目录"
      ;;
    opencode)
      remove_path "$HOME/.opencode/bin/$t" "opencode 二进制"
      ;;
  esac

  hash -r 2>/dev/null || true

  if [ "$DRY_RUN" != 1 ]; then
    if tool_version "$t" >/dev/null 2>&1; then
      warn "$t 仍可执行（$(tool_resolve "$t")），请手动清理"
    else
      ok "$t 已卸载干净"
    fi
  else
    printf '     （dry-run：未实际卸载）\n'
  fi
  printf '     配置文件保留未删：%s\n' "$(tool_config_path "$t")"
}

# ---------------------------------------------------------------- 预检
preflight() {
  local t tv
  step "预检"
  for t in $TOOLS; do
    if tv="$(tool_version "$t")"; then
      printf '  %-9s %s已安装%s  %-18s %-10s %s\n' \
        "$t" "$C_GRN" "$C_RST" "$tv" "$(kind_label "$(tool_install_kind "$t")")" "$(tool_resolve "$t")"
    else
      printf '  %-9s %s未安装%s\n' "$t" "$C_YEL" "$C_RST"
    fi
  done

  if [ "$FORCE" != 1 ] && [ "$CAN_PROMPT" != 1 ]; then
    printf '\n%s非交互环境：已安装的工具会被直接跳过。要全部重装请加 --upgrade。%s\n' "$C_DIM" "$C_RST"
  fi
}

# ---------------------------------------------------------------- doctor
cmd_doctor() {
  step "系统"
  printf '  %-16s %s\n' "发行版" "$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}" || echo unknown)"
  printf '  %-16s %s\n' "内核" "$(uname -r)"
  printf '  %-16s %s\n' "架构" "$(uname -m)"
  printf '  %-16s %s\n' "包管理器" "${PM:-未识别}"
  printf '  %-16s %s\n' "sudo" "${SUDO:-无（当前 uid $(id -u)）}"

  step "Node / npm"
  if command -v node >/dev/null 2>&1; then
    printf '  %-16s %s  (%s)\n' "node" "$(node -v)" "$(command -v node)"
  else
    printf '  %-16s %s\n' "node" "${C_RED}未安装${C_RST}"
  fi
  if command -v npm >/dev/null 2>&1; then
    printf '  %-16s %s\n' "npm" "$(npm -v 2>/dev/null)"
    printf '  %-16s %s\n' "npm prefix" "$(npm config get prefix 2>/dev/null)"
    printf '  %-16s %s\n' "npm registry" "$(npm config get registry 2>/dev/null)"
    printf '  %-16s %s\n' "全局目录可写" "$(npm_global_writable && echo yes || echo 'no（脚本会自动切到 ~/.npm-global）')"
  else
    printf '  %-16s %s\n' "npm" "${C_RED}未安装${C_RST}"
  fi

  step "工具"
  local t tv
  for t in codex claude opencode; do
    if tv="$(tool_version "$t")"; then
      printf '  %-9s %-18s %-12s %s\n' "$t" "$tv" "$(kind_label "$(tool_install_kind "$t")")" "$(tool_resolve "$t")"
    else
      printf '  %-9s %s\n' "$t" "未安装"
    fi
  done

  step "连通性"
  printf '  %-34s %s\n' "registry.npmmirror.com" "$(probe_url https://registry.npmmirror.com/ @openai/codex)"
  printf '  %-34s %s\n' "npmmirror node 镜像" "$(probe_url "https://registry.npmmirror.com/-/binary/node/latest-v${NODE_MAJOR}.x/")"
  printf '  %-34s %s\n' "gitee.com" "$(probe_url https://gitee.com/)"
  printf '  %-34s %s\n' "claude.ai（官方安装器）" "$(probe_url https://claude.ai/install.sh)"
  printf '  %-34s %s\n' "api.openai.com（Codex 端点）" "$(probe_url https://api.openai.com/v1/models)"

  step "配置位置"
  for t in codex claude opencode; do
    printf '  %-9s %s\n' "$t" "$(tool_config_path "$t")"
  done
  printf '\n%s连通性一栏 200/30x 表示通，FAIL 表示连不上。%s\n' "$C_DIM" "$C_RST"
}

# ---------------------------------------------------------------- main
main() {
  parse_args "$@"

  case "$CMD" in
    help)    usage; exit 0 ;;
    version) printf 'install-ai-cli.sh %s\n' "$SCRIPT_VERSION"; exit 0 ;;
  esac

  apply_proxy
  detect_env

  if [ "$CMD" = "doctor" ]; then
    cmd_doctor
    exit 0
  fi

  case "$CMD" in
    all) TOOLS="codex claude opencode" ;;
    *)   TOOLS="$CMD" ;;
  esac

  if [ "$DO_UNINSTALL" = 1 ]; then
    for t in $TOOLS; do uninstall_tool "$t"; done
    exit 0
  fi

  # 先预检再动手：让用户先看清三个工具的现状，再决定要不要重装
  detect_prompt_capability
  preflight

  ensure_base_deps
  ensure_node
  ensure_npm_prefix
  apply_registry

  local rc=0
  for t in $TOOLS; do
    install_tool "$t" || rc=1
  done

  step "完成"
  printf '  配置文件位置（按需填写 API 地址与密钥）：\n'
  for t in $TOOLS; do
    printf '    %-9s %s\n' "$t" "$(tool_config_path "$t")"
  done
  printf '\n%s提示：新装的命令在 %s，若当前 shell 找不到请执行 source ~/.bashrc 或重开终端。%s\n' \
    "$C_DIM" "$NPM_BIN_DIR" "$C_RST"

  return "$rc"
}

main "$@"
