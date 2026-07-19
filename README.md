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

The hardened launcher keeps **Chromium’s own process sandbox** enabled (no `--no-sandbox`, no `CAP_SYS_ADMIN`) by applying a custom seccomp profile, plus resource limits and a one-way clipboard.

```bash
./run-x11docker.sh --home --share "$HOME/Downloads"
```

Equivalents without the helper script:

```bash
x11docker --network --clipboard=c2h --limit --home \
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
x11docker --backend=podman --network --clipboard=c2h --limit --home \
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
2. **Custom seccomp** (`seccomp/chromium.json`) — Docker’s default seccomp blocks the `clone`/`unshare` patterns Chromium needs for its **namespace sandbox**. This profile is the moby default adjusted to allow only those sandbox syscalls **without** granting `CAP_SYS_ADMIN`. That is the same idea as Jess Frazelle’s classic `chrome.json`, kept current against a modern default profile.
3. **Chromium flags** — disable only the unusable setuid helper under `no-new-privileges`; leave the namespace sandbox on. Set `CHROMIUM_NO_SANDBOX=1` only if the host lacks unprivileged user namespaces or seccomp cannot be applied.
4. **Resource limits** — `--limit` (CPU/RAM), `--pids-limit=512`, large `--shm-size` so the browser does not need reckless workarounds.
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
| `seccomp/chromium.json` | Seccomp profile for Chromium’s namespace sandbox |

## Environment variables

| Variable | Default | Meaning |
|----------|---------|---------|
| `CHROMIUM_NO_SANDBOX` | `0` | `1` disables Chromium’s process sandbox |
| `CHROMIUM_USER_DATA_DIR` | `$HOME/.config/chromium` | Profile directory |
| `KEYBOARD_LAYOUT` | `us` | `setxkbmap` layout |
| `SECCOMP_PROFILE` | `./seccomp/chromium.json` | Override seccomp path |
| `X11DOCKER_CHROMIUM_IMAGE` | `chromium` | Image name |
| `SHM_SIZE` | `1g` | Docker `/dev/shm` size |
| `PIDS_LIMIT` | `512` | Max processes in the container |
| `READ_ONLY` | `0` | `1` enables read-only root + tmpfs |
| `DEBUG` | `0` | `1` traces the launcher |

## To do

- Trim packages further if a smaller image is needed.
- Optional Chromium enterprise policy pack for tighter web features.
