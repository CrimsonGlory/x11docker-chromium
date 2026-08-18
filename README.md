# x11docker-chromium

Run [Chromium](https://www.chromium.org/) inside Docker with [x11docker](https://github.com/mviereck/x11docker) for a tightly isolated GUI browser sandbox.

Inspired by [x11docker-cursor](https://github.com/CrimsonGlory/x11docker-cursor) and hardened using ideas from [Running Chromium in Docker Without Selling Your Soul](https://medium.com/code-and-coffee/running-chromium-in-docker-without-selling-your-soul-433e591802f2).

## Host dependencies

- docker (or podman)
- [x11docker](https://github.com/mviereck/x11docker)
- An X server option supported by x11docker (e.g. Xephyr, nxagent, or image `x11docker/xserver`)

Optional on the host: `xclip` (clipboard helpers).

## Build

```bash
docker build -t chromium .
```

## Run (recommended)

The hardened launcher keeps **Chromium’s own process sandbox** enabled (no `--no-sandbox`, no `CAP_SYS_ADMIN`) by applying a custom seccomp profile, plus a one-way clipboard and process/shm limits.

```bash
./run-x11docker.sh --home --share "$HOME/Downloads"
```

Equivalents without the helper script:

```bash
x11docker --network --clipboard=c2h --home \
  --share "$HOME/Downloads" \
  -- \
  --shm-size=1g \
  --pids-limit=512 \
  --security-opt seccomp=$(pwd)/seccomp/chromium.json \
  -- chromium
```

`--home` stores the Chromium profile under `~/.local/share/x11docker/chromium` (or the path you set with `--home=DIR`).

### Minimal (still with sandbox seccomp)

```bash
./run-x11docker.sh
# or
x11docker --network -- \
  --shm-size=1g \
  --security-opt seccomp=$(pwd)/seccomp/chromium.json \
  -- chromium
```

### Keyboard layout

If AltGr / non-US layout matters, pass your host layout (same pattern as x11docker-cursor):

```bash
KEYBOARD_LAYOUT=$(grep XKBLAYOUT /etc/default/keyboard | sed 's/XKBLAYOUT=//g' | tr -d '"') \
  ./run-x11docker.sh --home
```

### Performance / lag

Without GPU passthrough, nested X often only offers ancient GLX. Chromium then
spams `Unsupported GLX version (requires at least 1.3)`, kills the GPU process
in a loop, and feels very laggy. The entrypoint detects `/dev/dri` and:

- **no DRI** → `--disable-gpu` / software compositing (stops the crash loop)
- **with DRI** (`x11docker --gpu`) → hardware GL + `--ignore-gpu-blocklist`

Also prefer a large `--shm-size` (the launcher defaults to `1g`) so Chromium can
use `/dev/shm` instead of slow disk-backed shared memory. Resource capping with
x11docker `--limit` is **off by default** (enable with `LIMIT=1`) so software
rendering is not CPU-starved.

| Goal | How |
|------|-----|
| Best smoothness without host GPU | default software path; rebuild image after updating `run-chromium.sh` |
| GPU acceleration | `./run-x11docker.sh --gpu --home` |
| Force software GL | `CHROMIUM_GPU=0 ./run-x11docker.sh --home` |
| Cap CPU/RAM (~50%) | `LIMIT=1 ./run-x11docker.sh --home` |

Harmless noise in logs (not the lag): missing D-Bus, missing ALSA card (use
`--pulseaudio` for sound), GCM `DEPRECATED_ENDPOINT`.

### Optional features

| Goal | How |
|------|-----|
| GPU acceleration | `./run-x11docker.sh --gpu --home` |
| Sound | `./run-x11docker.sh --pulseaudio --home` (image includes `libpulse0`) |
| Webcam | `./run-x11docker.sh --webcam --home` |
| Read-only rootfs | `READ_ONLY=1 ./run-x11docker.sh --home` |
| Extra Chromium args / URL | `./run-x11docker.sh --home -- https://example.com` |
| Emergency: disable Chromium sandbox | `CHROMIUM_NO_SANDBOX=1 ./run-x11docker.sh` (weaker; avoid) |

Example with GPU and sound:

```bash
./run-x11docker.sh --gpu --pulseaudio --home --share "$HOME/Downloads"
```

### Podman

```bash
x11docker --backend=podman --network --clipboard=c2h --home \
  -- \
  --shm-size=1g \
  --pids-limit=512 \
  --security-opt seccomp=$(pwd)/seccomp/chromium.json \
  -- chromium
```

## Security model

### What we avoid

| Anti-pattern | Why |
|--------------|-----|
| `--no-sandbox` | Strips Chromium’s multi-process sandbox (last line of defense inside the container). |
| `--cap-add=SYS_ADMIN` | Effectively “new root”; unlocks mount/namespace escapes. |
| `--hostdisplay` | Shares host X `:0` — weak X isolation. |
| Full bidirectional clipboard | Can exfiltrate host clipboard content into a compromised browser. |

### What we do instead

1. **x11docker isolation** — nested X server, unprivileged host-mapped user, `--cap-drop=ALL`, `--security-opt=no-new-privileges`.
2. **Custom seccomp** (`seccomp/chromium.json`) — Docker’s default seccomp blocks the `clone`/`unshare` patterns Chromium needs for its **namespace sandbox**. This profile starts from the moby default, allows those sandbox syscalls **without** granting `CAP_SYS_ADMIN`, and is further trimmed so only syscalls justified by `linux_x86_64_syscalls_chromium_used.md` (`used?=true`) remain allowed (plus multi-arch/compat aliases). That is the same idea as Jess Frazelle’s classic `chrome.json`, kept current against Chromium’s documented outer surface.
3. **Chromium flags** — leave the namespace sandbox on; do **not** pass `--disable-setuid-sandbox` (that only triggers Chromium’s “unsupported flag” infobar and is unnecessary when seccomp allows the namespace sandbox). Under x11docker’s `no-new-privileges`, the setuid helper cannot elevate even if `chromium-sandbox` is installed. Set `CHROMIUM_NO_SANDBOX=1` only if the host lacks unprivileged user namespaces or seccomp cannot be applied.
4. **Resource limits** — `--pids-limit=512`, large `--shm-size` (default `1g`). Optional x11docker CPU/RAM cap via `LIMIT=1`.
5. **Clipboard** — default `c2h` (container → host only) in the launcher.
6. **Optional read-only rootfs** — `READ_ONLY=1` adds `--read-only` plus `noexec` tmpfs mounts (pair with `--home`).

### Requirements for the Chromium sandbox

- Host kernel allows unprivileged user namespaces (common on modern desktop kernels).
- Docker/podman applies `seccomp/chromium.json` (use `./run-x11docker.sh` or the documented `--security-opt`).
- Do **not** pass `--cap-default` / drop `no-new-privileges` unless you know you need them.

If Chromium refuses to start with a sandbox / namespace error, confirm the seccomp path is absolute and readable by the docker daemon, then only as a fallback:

```bash
CHROMIUM_NO_SANDBOX=1 ./run-x11docker.sh --home
```

## Why this exists

Browsers are high-risk software (JS, media codecs, extensions). Running them under x11docker gives a deployable, least-privilege GUI sandbox without sharing host display `:0` or using a full VM — and without the usual “just add `--no-sandbox`” footgun.

## Files

| File | Role |
|------|------|
| `Dockerfile` | Debian trixie + Chromium and GUI helpers |
| `run-chromium.sh` | In-container Chromium launch (sandbox-aware) |
| `run-x11docker.sh` | Host launcher with seccomp + hardening flags |
| `seccomp/chromium.json` | Seccomp profile for Chromium’s namespace sandbox (trimmed to used syscalls) |
| `linux_x86_64_syscalls_chromium_used.md` | Which x86_64 syscalls Chromium needs under an outer filter |

## Environment variables

| Variable | Default | Meaning |
|----------|---------|---------|
| `CHROMIUM_NO_SANDBOX` | `0` | `1` disables Chromium’s process sandbox |
| `CHROMIUM_GPU` | `auto` | `auto` = DRI detect; `0` software; `1` hardware flags |
| `CHROMIUM_DISABLE_DEV_SHM` | `0` | `1` forces `--disable-dev-shm-usage` (disk-backed shmem) |
| `CHROMIUM_BIN` | `/usr/lib/chromium/chromium` | Override Chromium ELF path (avoid Debian shell wrapper) |
| `CHROMIUM_USER_DATA_DIR` | `$HOME/.config/chromium` | Profile directory |
| `KEYBOARD_LAYOUT` | `us` | `setxkbmap` layout |
| `SECCOMP_PROFILE` | `./seccomp/chromium.json` | Override seccomp path |
| `X11DOCKER_CHROMIUM_IMAGE` | `chromium` | Image name |
| `SHM_SIZE` | `1g` | Docker `/dev/shm` size |
| `PIDS_LIMIT` | `512` | Max processes in the container |
| `LIMIT` | `0` | `1` enables x11docker `--limit` (CPU/RAM ~50%) |
| `READ_ONLY` | `0` | `1` enables read-only root + tmpfs |
| `DEBUG` | `0` | `1` traces the launcher |

## To do

- Trim packages further if a smaller image is needed.
- Optional Chromium enterprise policy pack for tighter web features.
