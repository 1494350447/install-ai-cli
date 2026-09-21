#!/usr/bin/env bash
# DeepSeek Harness (dsh) 一键安装 / 启动脚本
# 上游：https://github.com/deepseek-ai/deepseek-harness（master, MIT, developer preview）
# 生成：syl-oneclick-deploy
#
# 用法：
#   ./deploy.sh doctor      只做环境体检，不改动任何东西
#   ./deploy.sh install     克隆源码 + pnpm install + pnpm run build
#   ./deploy.sh up          后台启动 Web UI 并等待就绪
#   ./deploy.sh verify      安装/启动/健康检查/重启幂等 全流程实测
#   ./deploy.sh status      查看进程与端口状态
#   ./deploy.sh logs        跟踪日志
#   ./deploy.sh down        停止
#   ./deploy.sh reset [--purge]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${DSH_SRC:-$ROOT_DIR/checkout}"
LOG_DIR="$ROOT_DIR/logs"
LOG_FILE="$LOG_DIR/dsh.log"
PID_FILE="$ROOT_DIR/dsh.pid"
ENV_FILE="$ROOT_DIR/.env"

PORT="3080"
HOST="127.0.0.1"
WAIT="300"
REF="master"
PREBUILT=0
PURGE=0
USE_MIRROR=1

PNPM_PIN="11.7.0"
REPO_URL="https://github.com/deepseek-ai/deepseek-harness.git"
PREBUILT_PKG="@deepseek-ai/dsh"
REGISTRY="https://registry.npmmirror.com"
GH_MIRROR="${DSH_GH_MIRROR:-}"
PNPM=()

usage() { sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
step() { echo "[STEP] $*"; }
warn() { echo "[WARN] $*" >&2; }
die()  { echo "[FAIL] $*" >&2; exit 1; }
ok()   { echo "[ OK ] $*"; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --port) PORT="${2:?}"; shift 2 ;;
      --host) HOST="${2:?}"; shift 2 ;;
      --dir)  SRC_DIR="${2:?}"; shift 2 ;;
      --ref)  REF="${2:?}"; shift 2 ;;
      --wait) WAIT="${2:?}"; shift 2 ;;
      --prebuilt) PREBUILT=1; shift ;;
      --purge) PURGE=1; shift ;;
      --registry) REGISTRY="${2:?}"; shift 2 ;;
      --no-mirror) USE_MIRROR=0; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "未知参数：$1（用 --help 查看用法）" ;;
    esac
  done
  if [[ "$HOST" == "0.0.0.0" ]]; then
    die "dsh 明确不支持 --host 0.0.0.0，会直接报用法错误。请用 127.0.0.1 或具体网卡地址。"
  fi
}

load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
  fi
  PORT="${DSH_PORT:-$PORT}"
  HOST="${DSH_HOST:-$HOST}"
  REGISTRY="${DSH_NPM_REGISTRY:-$REGISTRY}"
  if [[ -n "${DSH_GH_MIRROR:-}" ]]; then GH_MIRROR="$DSH_GH_MIRROR"; fi
  if [[ "${DSH_USE_MIRROR:-1}" == "0" ]]; then USE_MIRROR=0; fi
}

setup_network() {
  if [[ "$USE_MIRROR" -eq 0 ]]; then
    ok "使用官方源（--no-mirror）"
    return 0
  fi
  export npm_config_registry="$REGISTRY"
  export COREPACK_NPM_REGISTRY="$REGISTRY"
  export npm_config_fetch_timeout="${npm_config_fetch_timeout:-120000}"
  export npm_config_fetch_retries="${npm_config_fetch_retries:-5}"
  export npm_config_fetch_retry_maxtimeout="${npm_config_fetch_retry_maxtimeout:-120000}"
  # 以下二进制不走 npm registry，需要各自指定国内镜像
  export ELECTRON_MIRROR="${ELECTRON_MIRROR:-https://npmmirror.com/mirrors/electron/}"
  export ELECTRON_BUILDER_BINARIES_MIRROR="${ELECTRON_BUILDER_BINARIES_MIRROR:-https://npmmirror.com/mirrors/electron-builder-binaries/}"
  export PLAYWRIGHT_DOWNLOAD_HOST="${PLAYWRIGHT_DOWNLOAD_HOST:-https://cdn.npmmirror.com/binaries/playwright}"
  export PLAYWRIGHT_CHROMIUM_DOWNLOAD_HOST="${PLAYWRIGHT_CHROMIUM_DOWNLOAD_HOST:-https://cdn.npmmirror.com/binaries/playwright}"
  export NODEJS_ORG_MIRROR="${NODEJS_ORG_MIRROR:-https://npmmirror.com/mirrors/node}"
  ok "已启用国内镜像源：$REGISTRY"
  ok "electron / playwright 二进制镜像：npmmirror"
}

check_node() {
  command -v node >/dev/null 2>&1 || die "未安装 Node.js（需要 ^22.19.0 || >=24.0.0）"
  local version major minor
  version="$(node -v | sed 's/^v//')"
  major="${version%%.*}"
  minor="$(cut -d. -f2 <<<"$version")"
  if [[ "$major" -gt 24 ]] || [[ "$major" -eq 24 ]] || { [[ "$major" -eq 22 ]] && [[ "$minor" -ge 19 ]]; }; then
    ok "Node.js v$version"
  else
    die "Node.js v$version 不满足 engines 要求 ^22.19.0 || >=24.0.0"
  fi
}

resolve_pnpm() {
  if command -v pnpm >/dev/null 2>&1 && [[ "$(pnpm --version 2>/dev/null)" == "$PNPM_PIN" ]]; then
    PNPM=(pnpm); ok "复用在 PATH 上的 pnpm $PNPM_PIN"; return 0
  fi
  # 仓库的 npm scripts 内部会裸调用 `pnpm`，所以必须在 PATH 上提供 pnpm 可执行文件。
  # 这里生成一个自包含 shim，避免修改用户全局 Node 安装。
  SHIM_DIR="$ROOT_DIR/.bin"
  mkdir -p "$SHIM_DIR"
  if command -v corepack >/dev/null 2>&1; then
    printf '#!/bin/sh\nexec corepack pnpm "$@"\n' > "$SHIM_DIR/pnpm"
    chmod +x "$SHIM_DIR/pnpm"
    export PATH="$SHIM_DIR:$PATH"
    PNPM=(pnpm)
    ok "通过 corepack 使用 package.json 锁定的 pnpm $PNPM_PIN（已生成 .bin/pnpm shim）"
    return 0
  fi
  if command -v npx >/dev/null 2>&1; then
    printf '#!/bin/sh\nexec npx --yes pnpm@%s "$@"\n' "$PNPM_PIN" > "$SHIM_DIR/pnpm"
    chmod +x "$SHIM_DIR/pnpm"
    export PATH="$SHIM_DIR:$PATH"
    PNPM=(pnpm)
    ok "通过 npx 使用 pnpm $PNPM_PIN（已生成 .bin/pnpm shim）"
    return 0
  fi
  die "找不到 pnpm，也没有 corepack / npx 可用"
}

port_listening() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltn "sport = :$PORT" 2>/dev/null | tail -n +2 | grep -q .
  else
    curl -s -o /dev/null --max-time 2 "http://$HOST:$PORT/" 2>/dev/null
  fi
}

http_code() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://$HOST:$PORT/" 2>/dev/null)" || code=""
  printf '%s' "${code:-000}"
}

# Web UI 需要启动时打印的一次性 token，裸访问 / 会返回 401。
# 因此 401 说明 HTTP 服务已经活着，属于就绪。
is_ready_code() { [[ "$1" =~ ^[23] ]] || [[ "$1" == "401" ]]; }

access_url() {
  grep -o "dsh web: http://[^ ]*" "$LOG_FILE" 2>/dev/null | tail -1 | sed 's/^dsh web: //'
}

# ---------- 原生二进制 ----------
# dsh 的 flock 绑定与 landlock 启动器不是本地编译出来的：上游 CI 编译好后随
# npm 平台包（@deepseek-ai/node-addon-system-<platform>）发布，消费者只需要
# 把 bin/ 放进平台包目录。所以本机没有 C 编译器也不该降级掉这部分。

detect_platform() {
  case "$(uname -s)/$(uname -m)" in
    Linux/x86_64 | Linux/amd64) NATIVE_PLATFORM="linux-x64" ;;
    Linux/aarch64 | Linux/arm64) NATIVE_PLATFORM="linux-arm64" ;;
    Darwin/x86_64) NATIVE_PLATFORM="darwin-x64" ;;
    Darwin/arm64) NATIVE_PLATFORM="darwin-arm64" ;;
    *) NATIVE_PLATFORM="" ;;
  esac
}

native_dir() { printf '%s/native/system/packages/%s' "$SRC_DIR" "$NATIVE_PLATFORM"; }

libc_variant() {
  node -p "process.report.getReport().header.glibcVersionRuntime ? 'glibc' : 'musl'" 2>/dev/null || echo glibc
}

# 需要哪些产物，读上游的 prebuilds.json，不凭经验猜。
native_required_paths() {
  local dir; dir="$(native_dir)"
  [[ -f "$dir/prebuilds.json" ]] || return 1
  node -e '
    const fs = require("node:fs")
    const spec = JSON.parse(fs.readFileSync(process.argv[1], "utf8"))
    const variant = process.argv[2]
    for (const b of spec.binaries) {
      if (b.libc !== undefined && b.libc !== variant) continue
      console.log(b.path)
    }
  ' "$dir/prebuilds.json" "$(libc_variant)"
}

native_missing() {
  local dir="$1" rel
  while read -r rel; do
    [[ -n "$rel" ]] || continue
    [[ -f "$dir/$rel" ]] || echo "$rel"
  done < <(native_required_paths)
}

verify_integrity() {
  local file="$1" expected="$2" actual
  [[ -n "$expected" ]] || { warn "registry 未提供 integrity，跳过校验"; return 0; }
  actual="$(node -e '
    const crypto = require("node:crypto")
    const fs = require("node:fs")
    const [algo] = process.argv[2].split("-", 1)
    const buf = fs.readFileSync(process.argv[1])
    console.log(algo + "-" + crypto.createHash(algo).update(buf).digest("base64"))
  ' "$file" "$expected")"
  if [[ "$actual" != "$expected" ]]; then
    warn "integrity 不匹配：期望 $expected，实际 $actual"
    return 1
  fi
  ok "已校验 integrity（$actual）"
}

ensure_native_prebuilt() {
  [[ "$PREBUILT" -eq 0 ]] || return 0
  if [[ -z "$NATIVE_PLATFORM" ]]; then
    warn "未知平台 $(uname -s)/$(uname -m)：跳过原生产物补齐"
    return 0
  fi
  local dir; dir="$(native_dir)"
  if [[ ! -f "$dir/package.json" ]]; then
    warn "上游没有 $NATIVE_PLATFORM 平台包：跳过原生产物补齐"
    return 0
  fi
  local missing; missing="$(native_missing "$dir")"
  if [[ -z "$missing" ]]; then
    ok "原生产物已就位（$NATIVE_PLATFORM / $(libc_variant)）"
    return 0
  fi
  local name version meta tarball integrity tmp
  name="$(node -p "require('$dir/package.json').name")"
  version="$(node -p "require('$dir/package.json').version")"
  step "补齐原生产物：$name@$version（缺少：$(tr '\n' ' ' <<<"$missing"))"
  meta="$(curl -fsSL --max-time 60 "${REGISTRY%/}/$name" 2>/dev/null || true)"
  [[ -n "$meta" ]] || die "无法读取 ${REGISTRY%/}/$name 的元数据（网络或镜像源问题）"
  tarball="$(printf '%s' "$meta" | node -e '
    let s = ""
    process.stdin.on("data", (d) => { s += d }).on("end", () => {
      const v = JSON.parse(s).versions[process.argv[1]]
      if (!v) process.exit(3)
      console.log(v.dist.tarball)
    })
  ' "$version")" || die "镜像源上找不到 $name@$version"
  integrity="$(printf '%s' "$meta" | node -e '
    let s = ""
    process.stdin.on("data", (d) => { s += d }).on("end", () => {
      const v = JSON.parse(s).versions[process.argv[1]]
      console.log((v.dist.integrity || ""))
    })
  ' "$version")"
  tmp="$(mktemp -d)"
  step "下载：$tarball"
  curl -fsSL --max-time 300 -o "$tmp/pkg.tgz" "$tarball" || { rm -rf "$tmp"; die "下载失败：$tarball"; }
  verify_integrity "$tmp/pkg.tgz" "$integrity" || { rm -rf "$tmp"; die "下载内容与 registry 声明的 integrity 不符，已中止"; }
  tar -xzf "$tmp/pkg.tgz" -C "$tmp" package/bin || { rm -rf "$tmp"; die "解包失败"; }
  mkdir -p "$dir/bin"
  cp -a "$tmp/package/bin/." "$dir/bin/"
  rm -rf "$tmp"
  [[ -f "$dir/bin/landlock-run" ]] && chmod +x "$dir/bin/landlock-run"
  missing="$(native_missing "$dir")"
  [[ -z "$missing" ]] || die "补齐后仍然缺少：$(tr '\n' ' ' <<<"$missing")"
  ok "原生产物已补齐（$name@$version）"
}

# 安装期就跑一次运行期冒烟：原生模块加载不了的话，绝不留给用户启动时才炸。
smoke_native() {
  [[ "$PREBUILT" -eq 0 ]] || return 0
  [[ -f "$SRC_DIR/package.json" ]] || return 0
  step "运行期冒烟：确认原生模块真的能加载"
  local dir entry_lib js rc
  dir="$(native_dir)"
  entry_lib="$dir/../entry/lib"
  js="$(cat <<'JS'
const path = require('node:path')
const { pathToFileURL } = require('node:url')
const [entryLib, platformDir, libc] = process.argv.slice(1)
const binding = require(path.join(platformDir, 'bin', libc, 'system.node'))
if (typeof binding.tryLock !== 'function') {
  console.error('flock 绑定没有导出 tryLock')
  process.exit(1)
}
import(pathToFileURL(path.join(entryLib, 'flock.js')).href).then(async (mod) => {
  const { openSync, closeSync, mkdtempSync, rmSync } = require('node:fs')
  const os = require('node:os')
  const work = mkdtempSync(path.join(os.tmpdir(), 'dsh-smoke-'))
  const fd = openSync(path.join(work, 'lock'), 'w')
  try {
    await mod.tryLockExclusive(fd)
    console.log('flock 绑定：加载成功，且能真正取得排他锁')
  } finally {
    closeSync(fd)
    rmSync(work, { recursive: true, force: true })
  }
  const landing = await import(pathToFileURL(path.join(entryLib, 'index.js')).href)
  const enforcement = landing.probe(path.join(platformDir, 'bin', 'landlock-run'))
  console.log('landlock 启动器：' + enforcement)
  if (enforcement === 'unusable') process.exit(4)
}, (e) => {
  console.error('冒烟失败：' + (e && e.message ? e.message : e))
  process.exit(2)
})
JS
)"
  set +e
  ( cd "$SRC_DIR" && node -e "$js" "$entry_lib" "$dir" "$(libc_variant)" )
  rc=$?
  set -e
  case "$rc" in
    0) ok "原生模块冒烟通过" ;;
    4)
      warn "原生模块可加载，但 landlock 内核强制不可用：沙箱隔离能力降级，必须写进部署报告"
      ;;
    *) die "原生模块加载失败（退出码 $rc）。这就是启动时报 'Cannot find module .../system.node' 的前置信号，先修它再启动。" ;;
  esac
}

cmd_doctor() {
  step "环境体检"
  check_node
  command -v git >/dev/null 2>&1 || die "未安装 git（需要 2.26+）"
  ok "git $(git --version | awk '{print $3}')"
  [[ "$PREBUILT" -eq 1 ]] || resolve_pnpm
  ok "磁盘可用空间：$(df -h "$ROOT_DIR" | tail -1 | awk '{print $4}')"
  ok "内存：$(free -g 2>/dev/null | awk '/^Mem:/{print $2"GB"}')"
  if port_listening; then
    warn "端口 $PORT 已被占用（可能是上次没停干净）"
  else
    ok "端口 $PORT 空闲"
  fi
  if [[ -n "${DEEPSEEK_API_KEY:-}" ]]; then
    ok "检测到 DEEPSEEK_API_KEY"
  else
    warn "未设置 DEEPSEEK_API_KEY：Web UI 能启动，但无法真正调用模型"
  fi
  if [[ "$PREBUILT" -eq 0 && -f "$SRC_DIR/package.json" ]]; then
    local miss
    miss="$(native_missing "$(native_dir)")"
    if [[ -z "$miss" ]]; then
      ok "原生产物已就位（$NATIVE_PLATFORM / $(libc_variant)）"
    else
      warn "原生产物缺失：$(tr '\n' ' ' <<<"$miss")（./deploy.sh install 会从上游预编译平台包补齐）"
    fi
  fi
  ok "体检结束"
}

ensure_checkout() {
  if [[ -d "$SRC_DIR/.git" ]]; then
    step "复用已有 checkout：$SRC_DIR"
    return 0
  fi
  if [[ -d "$SRC_DIR" && -n "$(ls -A "$SRC_DIR" 2>/dev/null)" ]]; then
    step "复用已有目录（非 git 仓库）：$SRC_DIR"
    return 0
  fi
  step "克隆 $REPO_URL（ref=$REF）到 $SRC_DIR"
  mkdir -p "$(dirname "$SRC_DIR")"
  local url="$REPO_URL"
  if [[ -n "$GH_MIRROR" ]]; then
    url="${GH_MIRROR%/}/$REPO_URL"
    warn "使用 GitHub 加速前缀克隆：$GH_MIRROR"
  fi
  git clone --depth 1 --branch "$REF" "$url" "$SRC_DIR" \
    || die "克隆失败。可选：用 --dir 指向本地已有 checkout；或用 DSH_GH_MIRROR=<加速前缀> 重试（第三方加速服务会中转你的代码，需自行评估信任）"
}

cmd_install() {
  cmd_doctor
  ensure_checkout
  step "安装依赖：pnpm install --frozen-lockfile（会执行仓库的 postinstall，配置本地 git hooks）"
  local install_args=(--frozen-lockfile)
  # pnpm 11 不读取 npm_config_registry 环境变量，必须用 --registry 显式传入
  if [[ "$USE_MIRROR" -eq 1 ]]; then install_args+=(--registry "$REGISTRY"); fi
  ( cd "$SRC_DIR" && "${PNPM[@]}" install "${install_args[@]}" )
  step "构建产物：pnpm run build（Web UI 生产运行需要）"
  if ! ( cd "$SRC_DIR" && "${PNPM[@]}" run build ); then
    if ! command -v cc >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1; then
      warn "完整构建失败：build:native-system 需要 C 编译器，本机没有"
      warn "但 dsh 的原生产物（flock 绑定 + landlock 启动器）由上游 CI 预编译后随 npm 平台包发布，消费者本来就不需要编译器。"
      warn "所以不降级跳过原生产物，改为：构建 TS/前端产物 + 补齐上游预编译产物。"
      ( cd "$SRC_DIR" && "${PNPM[@]}" run build:lib ) || die "回退构建 build:lib 失败"
      ( cd "$SRC_DIR" && "${PNPM[@]}" run build:web ) || die "回退构建 build:web 失败"
      warn "要跑完整本地构建（可选，不影响运行）：sudo apt install -y build-essential 后重跑 ./deploy.sh install"
    else
      die "构建失败，请查看上方日志"
    fi
  fi
  ensure_native_prebuilt
  smoke_native
  ok "安装完成。下一步：./deploy.sh up"
}

cmd_up() {
  [[ -z "$(running_pid)" ]] || die "已在运行（pid $(running_pid)），先执行 ./deploy.sh down"
  mkdir -p "$LOG_DIR"
  local launcher=()
  if [[ "$PREBUILT" -eq 1 ]]; then
    launcher=(npx --yes "$PREBUILT_PKG")
  else
    [[ -f "$SRC_DIR/package.json" ]] || die "还没安装（$SRC_DIR 不存在），先执行 ./deploy.sh install"
    resolve_pnpm
    local miss
    miss="$(native_missing "$(native_dir)")"
    [[ -z "$miss" ]] || die "原生产物缺失：$(tr '\n' ' ' <<<"$miss")。直接启动会报 'Cannot find module .../system.node'。先执行 ./deploy.sh install（会从上游预编译平台包下载并校验 integrity）"
    launcher=("${PNPM[@]}" dsh)
  fi
  step "启动：${launcher[*]} web --host $HOST --port $PORT --no-open"
  local cwd="$SRC_DIR"
  if [[ "$PREBUILT" -eq 1 ]]; then cwd="$ROOT_DIR"; fi
  # setsid 让服务脱离当前会话与进程组，父 shell 退出时不会被一起回收。
  local detach=()
  if command -v setsid >/dev/null 2>&1; then detach=(setsid); fi
  ( cd "$cwd" && nohup "${detach[@]}" "${launcher[@]}" web --host "$HOST" --port "$PORT" --no-open \
      >>"$LOG_FILE" 2>&1 </dev/null & echo $! >"$PID_FILE" )
  ok "已后台启动，pid=$(cat "$PID_FILE")，日志：$LOG_FILE"
  wait_ready
}

# pnpm 会派生子进程，PID 文件记录的顶层进程可能先退出变孤儿，
# 所以以命令行匹配为准（host/port 唯一，避免误杀）。
matching_pids() {
  pgrep -f "(dsh web|bin\.ts web) --host $HOST --port $PORT" 2>/dev/null || true
}

running_pid() {
  local pids
  pids="$(matching_pids)"
  [[ -n "$pids" ]] || return 1
  echo "${pids%%$'\n'*}"
}

wait_ready() {
  local deadline=$((SECONDS + WAIT)) grace=$((SECONDS + 15)) code
  step "等待就绪（http://$HOST:$PORT/ ，上限 ${WAIT}s）"
  # 启动器（corepack/pnpm）需要 fork+exec 才出现 dsh 进程，刚启动的瞬间进程表里
  # 可能还看不到，所以先给一个宽限期；在这里直接判死会误报"进程没有在运行"。
  while [[ -z "$(matching_pids)" ]]; do
    if (( SECONDS >= grace )); then
      echo "--- 日志尾部 ---" >&2; tail -n 30 "$LOG_FILE" >&2 || true
      die "启动后 15s 内没有出现 dsh 进程，启动失败"
    fi
    sleep 1
  done
  while (( SECONDS < deadline )); do
    if [[ -z "$(matching_pids)" ]]; then
      echo "--- 日志尾部 ---" >&2; tail -n 30 "$LOG_FILE" >&2 || true
      die "进程已退出，启动失败"
    fi
    code="$(http_code)"
    if is_ready_code "$code"; then
      ok "服务已就绪（HTTP $code）"
      local url; url="$(access_url)"
      if [[ -n "$url" ]]; then
        ok "访问地址（含 token，直接复制到浏览器）：$url"
      else
        ok "访问地址：http://$HOST:$PORT/"
      fi
      return 0
    fi
    sleep 2
  done
  echo "--- 日志尾部 ---" >&2; tail -n 30 "$LOG_FILE" >&2 || true
  die "等待就绪超时（${WAIT}s），最后 HTTP 状态码 $code"
}

cmd_status() {
  local pid
  if pid="$(running_pid)"; then
    ok "运行中，pid=$pid"
    # 匹配到的第一个 pid 往往只是包装进程（corepack/pnpm），原生模块加载在真正的
    # node 子进程里，所以要遍历所有匹配到的进程去找证据。
    local mapped="" p hit
    while read -r p; do
      [[ -n "$p" ]] || continue
      hit="$(grep -o "/[^ ]*system\.node" "/proc/$p/maps" 2>/dev/null | sort -u | head -1 || true)"
      if [[ -n "$hit" ]]; then mapped="$hit"; break; fi
    done <<<"$(matching_pids)"
    if [[ -n "$mapped" ]]; then
      ok "原生模块已加载：$mapped"
    else
      warn "进程内存里没有 system.node（可能尚未用到 flock，或原生产物缺失）"
    fi
  else
    warn "没有运行中的 dsh 进程"
  fi
  port_listening && ok "端口 $PORT 正在监听" || warn "端口 $PORT 未监听"
  local code; code="$(http_code)"
  if is_ready_code "$code"; then
    ok "HTTP 状态码：$code（就绪；401 = 需要凭据）"
  else
    warn "HTTP 状态码：$code（未就绪）"
  fi
  local url; url="$(access_url)"
  [[ -n "$url" ]] && ok "最近一次启动的访问地址：$url"
  return 0
}

cmd_logs() { [[ -f "$LOG_FILE" ]] || die "还没有日志：$LOG_FILE"; tail -n 100 -f "$LOG_FILE"; }

# 授权访问验证。只看裸访问会把"就绪但需要凭据"误判成失败；只看 token 那一步会
# 把 303 误判成没通过。正确链路是：裸访问 401/2xx/3xx → token 换 cookie → 带 cookie 打开 UI。
verify_web_access() {
  local base="http://$HOST:$PORT/" jar="$LOG_DIR/.verify-cookies"
  local bare url token step1 step2
  rm -f "$jar"
  bare="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$base" 2>/dev/null || true)"
  is_ready_code "$bare" || die "裸访问 $base 返回 ${bare:-000}，服务未就绪"
  ok "裸访问根路径：HTTP $bare（401 = 已就绪但需要凭据）"
  url="$(access_url)"
  token="${url##*token=}"
  if [[ -z "$token" || "$token" == "$url" ]]; then
    warn "日志里没找到启动 token，跳过授权访问验证"
    return 0
  fi
  step1="$(curl -s -c "$jar" -o /dev/null -w '%{http_code}' --max-time 5 "$base?token=$token" 2>/dev/null || true)"
  if [[ "$step1" != "303" && ! "$step1" =~ ^2 ]]; then
    rm -f "$jar"
    die "用启动 token 换取授权 cookie 失败：HTTP ${step1:-000}"
  fi
  ok "启动 token 换取授权 cookie：HTTP $step1"
  step2="$(curl -s -b "$jar" -o /dev/null -w '%{http_code}' --max-time 10 "$base" 2>/dev/null || true)"
  rm -f "$jar"
  [[ "$step2" =~ ^2 ]] || die "带授权 cookie 打开 UI 失败：HTTP ${step2:-000}"
  ok "带授权 cookie 打开 UI：HTTP $step2"
}

cmd_down() {
  local pids
  pids="$(matching_pids)"
  if [[ -z "$pids" ]]; then
    warn "没有运行中的 dsh 进程"
    rm -f "$PID_FILE"
    return 0
  fi
  step "停止进程：$(tr '\n' ' ' <<<"$pids")（SIGTERM，最多等 10s）"
  while read -r pid; do
    [[ -n "$pid" ]] && kill -TERM "$pid" 2>/dev/null || true
  done <<<"$pids"
  for _ in $(seq 1 20); do
    [[ -z "$(matching_pids)" ]] && break
    sleep 0.5
  done
  local left
  left="$(matching_pids)"
  if [[ -n "$left" ]]; then
    warn "仍在运行，发送 SIGKILL：$(tr '\n' ' ' <<<"$left")"
    while read -r pid; do
      [[ -n "$pid" ]] && kill -KILL "$pid" 2>/dev/null || true
    done <<<"$left"
  fi
  rm -f "$PID_FILE"
  ok "已停止"
}

cmd_verify() {
  cmd_doctor
  [[ -f "$SRC_DIR/package.json" ]] || cmd_install
  cmd_up
  local first_code; first_code="$(http_code)"
  sleep 2
  cmd_down
  if port_listening; then die "down 之后端口 $PORT 仍在监听，清理不干净"; fi
  ok "清理干净：端口已释放"
  cmd_up
  sleep 2
  ok "重启后 HTTP 状态码：$(http_code)（首次为 $first_code）"
  verify_web_access
  echo "[PASS] 安装、启动、授权访问、停止、重启全部通过"
}

cmd_reset() {
  cmd_down
  rm -f "$PID_FILE"
  if [[ "$PURGE" -eq 1 ]]; then
    warn "将删除 checkout 与所有依赖（保留 .env）：$SRC_DIR"
    echo "5 秒内可 Ctrl-C 取消..." >&2
    sleep 5
    rm -rf "$SRC_DIR"
    ok "已删除 $SRC_DIR"
  else
    ok "已停止并清理运行态；要删除 checkout 请用 ./deploy.sh reset --purge"
  fi
}

command="${1:-help}"
shift || true
parse_args "$@"
load_env
detect_platform
setup_network
case "$command" in
  doctor) cmd_doctor ;;
  install) cmd_install ;;
  up) cmd_up ;;
  down) cmd_down ;;
  status) cmd_status ;;
  logs) cmd_logs ;;
  verify) cmd_verify ;;
  reset) cmd_reset ;;
  help|-h|--help) usage ;;
  *) die "未知命令：$command（用 --help 查看用法）" ;;
esac
