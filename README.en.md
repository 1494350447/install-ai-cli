# install-ai-cli

[简体中文](README.md) | [English](README.en.md) | [Deutsch](README.de.md) | [Français](README.fr.md)

One-command Linux installer for **Codex CLI** / **Claude Code** / **opencode** / **DeepSeek Harness (dsh)** / **OpenClaw**, designed for mainland China's network environment.

A dependency-free bash script that clears, in one go, the pitfalls you hit when installing these tools in that environment: Node too old, npm unreachable, platform binaries failing to download, GitHub connections reset.

> dsh and openclaw are not the same kind of tool as the first three: after installation they **still need to be started manually** — they are not CLIs that finish when the command returns (dsh is a long-running web service, openclaw is a gateway). So **neither is included in `all`**. See their respective sections below.

## Features

- **Preflight first**: lists the current state of each tool; already-installed tools are **not overwritten silently** but asked one by one "uninstall and reinstall?" (`y` / `N` / `a` / `q`)
- **Three-level Node fallback**: nvm (Gitee mirror) → npmmirror tarball direct install → explicit error with manual guidance
- **Does not touch your global npm registry**: uses `--registry` only temporarily during installation. To change it permanently, pass `--set-registry` explicitly
- **No sudo**: global packages always go to `~/.npm-global`, avoiding root ownership that would require sudo for later upgrades
- **Three-level npm registry fallback**: npmmirror → Tencent Cloud → official
- **Works on any distribution**: apt / dnf / yum / pacman / apk / zypper
- **Idempotent**: safe to rerun, already-installed tools are not installed again

## Quick start

```bash
# Download
curl -fsSL <raw URL of this repo>/install-ai-cli.sh -o install-ai-cli.sh

# Run a health check and see the current state first
bash install-ai-cli.sh doctor

# Install
bash install-ai-cli.sh codex
bash install-ai-cli.sh all
```

> This repository is **private**; curling the raw link directly requires a token. Authentication can be dropped once it is public.

## Commands

| Command | Purpose |
|---|---|
| `codex` | Install OpenAI Codex CLI |
| `claude` | Install Claude Code |
| `opencode` | Install opencode |
| `dsh` | Install DeepSeek Harness |
| `openclaw` | Install OpenClaw |
| `all` | Install all three CLIs above (**does not include dsh / openclaw**) |
| `doctor` | Health check: system, Node/npm, tool status, network connectivity |
| `version` | Print script version |
| `help` | Help |

`dsh` and `openclaw` also support `--uninstall`, and both **only remove the npm package, never touching user data**: `~/.dsh` (profiles and sessions) and `~/.openclaw` (config, agents, workspace, sqlite state) are never touched by the script.

When installing `openclaw` on its own, if you do not explicitly pass `--node-major`, the script **automatically raises Node to 24** — it requires `>=24.16.0 <25 || >=26.1.0`, and the default 22 installs but cannot start.

## Options

| Option | Description |
|---|---|
| `--reinstall` / `-f` / `--force` / `--upgrade` | Skip prompts; uninstall and reinstall everything already installed |
| `-y` / `--yes` | Non-interactive: skip everything already installed, do not reinstall |
| `--uninstall` | Uninstall the specified tool (keeps config files, removes binaries only) |
| `--registry <URL>` | npm registry, default `https://registry.npmmirror.com` |
| `--node-mirror <URL>` | Node binary source |
| `--node-major <N>` | Node major version, default 22 |
| `--no-node` | Skip Node installation/upgrade (use when Node ≥ 22 is already installed) |
| `--native` | Install Claude Code via the official curl installer (npm is used by default; more reliable in mainland China) |
| `--set-registry` | Permanently write the npm global registry (global config is not changed by default) |
| `--proxy <URL>` | Use a proxy, e.g. `http://127.0.0.1:7897` |
| `-n` / `--dry-run` | Print the commands that would run; make no changes |
| `-v` / `--verbose` | Print every command executed |

## Behavior when already installed

The script never silently overwrites an existing installation. It runs a preflight first:

```
── Preflight ──
  codex     not installed
  claude    installed  2.1.278     official installer  /home/u/.local/bin/claude
  opencode  installed  1.18.31     npm                 /home/u/.local/bin/opencode
```

Then it asks separately for each installed tool:

```
claude is installed: 2.1.278 (official installer)
  Uninstall and reinstall?
    [y] uninstall and reinstall    [N] skip    [a] reinstall the other installed tools too    [q] quit
  Choose [y/N/a/q] >
```

- Enter = skip; only `y`/`yes` triggers a reinstall
- `a` avoids being asked three times in a row in `all` mode
- In a non-interactive environment (`-y`, CI, no controlling terminal), already-installed tools are skipped automatically with a hint to add `--upgrade`
- Uninstalling **deletes only explicit paths**, logging every deletion; config files are always kept

## Supported environments

- **Distributions**: Debian/Ubuntu, RHEL/CentOS/Rocky/Alma, Fedora, Arch, Alpine, openSUSE
- **Architectures**: x86_64, aarch64/arm64, armv7l, ppc64le, s390x
- **Node**: ≥ 22 required (installed automatically by the script). There is no official Node build for LoongArch; the script reports an explicit error and tells you to use `--no-node`
- **Node (dsh only)**: dsh requires `^22.19.0 || >=24.0.0`, stricter than above. The script checks it separately and explains what to do when it is not satisfied. Note that **Node 23.x is rejected** — it satisfies `>=22` but falls outside `>=24.0.0`
- **Node (openclaw only)**: openclaw requires `>=24.16.0 <25 || >=26.1.0`, even stranger than dsh — **24.x has a `.16` patch floor, and the whole 25.x line is excluded**. So 22.x / 23.x / 24.0–24.15 / 25.x all fail to start. When installing openclaw alone without an explicit `--node-major`, the script raises Node to 24 (currently the highest is 24.21.0, inside the range)

## Pitfalls of the mainland-China network (already handled)

**1. The official npm registry is unreachable** → use npmmirror; on failure switch automatically to Tencent Cloud, then to the official registry.

**2. Node binaries are hard to download** → nvm itself is cloned from the Gitee mirror; Node tarballs come from npmmirror. **Note that the `latest-vN.x/` directory listing is a stale snapshot**: in testing, npmmirror's `latest-v24.x/` listed only up to 24.9.0, while 24.10.0–24.21.0 truly exist and are downloadable under `vX.Y.Z/` (control: both `v24.99.99/` and `v23.99.0/` return 404, confirming those 200s are not blanket responses). So the script instead reads `index.json` to resolve the highest patch version — that file is complete (866 entries on npmmirror, 863 on Tencent; nvm itself reads it too) — and then builds the download URL under `vX.Y.Z/`. Only when a mirror does not provide `index.json` does it fall back to that stale listing, with an explicit warning.

**3. `npmmirror.com/mirrors/node/...` is a 302 redirect**, and following it yields no parseable file listing. To fetch the listing, use `https://registry.npmmirror.com/-/binary/node/...`. (`index.json` is also a 302 to the CDN; the script's downloads and probes all pass `-L`.)

**4. GitHub Releases are basically unreachable directly** → all tools prefer npm packages (platform binaries are shipped through npm optionalDependencies) instead of fetching release artifacts from GitHub. openclaw's `dist/` is a self-contained bundle; every github.com link in `dist/` is a documentation or issue reference, with no download endpoint.

## What to do after installation

The script solves only the **download** problem, not the **can it actually run** problem. These tools all need their own API endpoint and key configured after installation, and the official endpoints are usually unreachable directly in mainland China:

| Tool | Config file |
|---|---|
| codex | `~/.codex/config.toml` |
| claude | `~/.claude/settings.json` |
| opencode | `~/.config/opencode/opencode.jsonc` |
| dsh | `~/.dsh/` (directory for profiles and sessions) |
| openclaw | `~/.openclaw/` (directory for `openclaw.json`, `.env`, `agents/`, `workspace`, sqlite state) |

The "Connectivity" column of `bash install-ai-cli.sh doctor` tells you which endpoints are reachable and which are not.

## Using dsh

The script only handles **installation**, not running. Start it yourself after installing:

```bash
dsh web --host 127.0.0.1 --port 3080
```

- It prints a **token-bearing URL** in the terminal; copy it into a browser
- **Runs in the foreground**; `Ctrl-C` stops it
- Change the port with `--port`

Two more things:

1. **Set `DEEPSEEK_API_KEY`**, otherwise the UI opens but cannot call models. `doctor` tells you whether it is set.
2. **`--host 0.0.0.0` is not supported**; dsh errors out directly. It only accepts `127.0.0.1` or a concrete interface address.

> Version management, logging, auto-start and the like for dsh are out of scope for this script. `dsh -h` and `dsh web --help` are upstream's own help.

## Using openclaw

Again, installation only. Configure it once after installing, then start the gateway:

```bash
openclaw onboard     # first-time configuration (models, channels, etc.)
openclaw gateway     # start the gateway in the foreground; Ctrl-C stops it
```

If you do not want to run the service and just want to ask one question:

```bash
openclaw agent --message "..."
```

For troubleshooting use `openclaw doctor` and `openclaw status`; `--help` / `--version` are upstream's own help.

A few reminders:

1. **Config, agents, workspace and sqlite state all live in `~/.openclaw`**. Uninstalling only removes the npm package and never touches this directory.
2. **It is big**: the tarball is about 72 MB, and about 222 MB unpacked (over 6,700 files under `dist/`). Installation takes noticeably longer than the others.
3. **The Node requirement is odd**: `>=24.16.0 <25 || >=26.1.0`. 25.x is explicitly excluded, and 24.x needs `.16` or above.

## Known limitations

- **The npm route for Claude Code has been deprecated by the vendor** (since January 2026). The package still works but no longer auto-updates; upgrades require rerunning `--upgrade`. For a native install, add `--native`.
- **npm 12 blocks install scripts by default** (`postinstall`). codex / claude / opencode rely on `postinstall` to link platform binaries into `bin/`, and openclaw's `postinstall` trims stale files under `dist/` — being blocked can leave a "works but incomplete" state. The script **does not handle this yet** — `--version` is not a reliable health check for these packages. npm 11.16–11.x only warns and still runs scripts, so it is unaffected.
- **If an older version is first on PATH after installing the package** (for example installed by the system package manager), the script warns but does not uninstall it for you.
- **dsh is currently a developer preview** (npm publishes it as `-rc` / `-alpha`); upstream explicitly marks it developer preview and behavior may change.
- **Do not probe the dsh version with `dsh --version`**: it is an application launcher, and upstream specifies that "arguments the launcher does not recognize are passed to the profile"; running it directly may actually bring up a web profile and hang the preflight. The script instead reads the `package.json` of the installed package, and only falls back to `--version` (with a 5-second timeout) when that cannot be read.
- **dsh's dependency tree is large** (73 production dependencies). During crawling, none were missing on mainland mirrors, but installation is slower than codex / claude / opencode.
- **dsh is installed from the npm prebuilt package only; no source build is provided**. This script does not clone the repository, install pnpm or compile. To modify dsh's source, clone upstream yourself.
- **openclaw is installed from the npm package only**, with no source build (upstream also has `openclaw.ai/install.sh`, which this script does not use).
- **openclaw does not start itself after installation**, and it is a **gateway / long-running service** (Telegram, Discord, Slack, WhatsApp and other channels + browser control + cron), not a fire-and-forget CLI. The script only installs.
- **openclaw's transitive dependencies were not exhaustively verified**. Only its 66 **direct** dependencies were checked version by version for complete availability on mainland mirrors; npmmirror syncs everything, so the risk is low, but unproven.
- **openclaw's `bin/` and `--version` probing are reliable** (upstream docs state that `--help` / `--version` take a fast path), so it does not need the `package.json` workaround that dsh needs.

## Status

- **Node version resolution (v1.2.1)**: previously the highest patch version was picked from the `latest-vN.x/` listing, but that listing is stale on mirrors — `--node-major 24` installed 24.9.0 instead of 24.21.0. Now reads `index.json`. Actually downloaded and unpacked 24.21.0 under Git Bash (`node_version.h` confirmed 24.21.0), and verified the downgrade path separately (simulated a mirror without `index.json`, confirming the warning and correct fallback to the old layout)
- Verified under Git Bash on Windows: syntax, `doctor`, `--dry-run`, `--uninstall`, non-interactive skip, answer parsing (`y/N/a/q`)
- Actually installed opencode via the npm route on Linux (npm 11.19.0 / Node v24.21.0)
- **dsh part**: 9 version cases for `node_satisfies_dsh` (including the Node 23.x that must be rejected), the install/uninstall integration paths, and "uninstall must not touch `~/.dsh`", all run with fake node/npm + a sandboxed HOME
- **openclaw part (v1.3.0)**: 13 version cases for `node_satisfies_openclaw` (including the 25.x and 24.15 that must be rejected), the four Node auto-raise scenarios (standalone install / explicit `--node-major 22` / explicit 26 / not raising when installing dsh), and a sandboxed test of "uninstall must not touch `~/.openclaw`". A real bug was found and fixed during testing: `27.0.0` should be accepted by `>=26.1.0`, but the original implementation rejected it because it was written as "major ≥ 26 and minor ≥ 1"
- **All write paths have not yet been run end to end in a complete Linux environment** (`nvm install`, `tar -xJf`, the npm installs of each tool)
- **dsh's npm install and `dsh web` startup have not been run on real hardware**. `@deepseek-ai/dsh` installability was verified at the npm metadata level (73 production dependencies with zero gaps on mainland mirrors, platform binaries shipped properly via optionalDependencies), but a final real-machine confirmation is still needed
- **openclaw's npm install and `openclaw gateway` startup have not been run on real hardware**. Likewise verified only at the npm metadata level (66 direct dependencies at exact versions with zero gaps on mainland mirrors; github.com links in `dist/` are documentation references rather than download endpoints), and the actual download and unpack of the 72 MB package still needs real-machine confirmation

## License

Not specified.
