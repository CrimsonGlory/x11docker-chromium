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
  --shm-size=3g \
  --pids-limit=4096 \
  --security-opt seccomp=$(pwd)/seccomp/chromium.json \
  -- chromium
```

`--home` stores the Chromium profile under `~/.local/share/x11docker/chromium` (or the path you set with `--home=DIR`).

### Minimal (still with sandbox seccomp)

```bash
./run-x11docker.sh
# or
x11docker --network -- \
  --shm-size=3g \
  --security-opt seccomp=$(pwd)/seccomp/chromium.json \
  -- chromium
```

### Keyboard layout

`run-x11docker.sh` auto-detects the host layout from `/etc/default/keyboard`
(`XKBLAYOUT`) and passes it into the container for `setxkbmap`. Override if
needed:

```bash
KEYBOARD_LAYOUT=de ./run-x11docker.sh --home
# optional: XKB_OPTIONS=lv3:ralt_switch (default)
```

### Performance / lag

Without GPU passthrough, nested X often only offers ancient GLX. Chromium then
spams `Unsupported GLX version (requires at least 1.3)`, kills the GPU process
in a loop, and feels very laggy. The entrypoint detects `/dev/dri` and:

- **no DRI** → `--disable-gpu` / software compositing (stops the crash loop)
- **with DRI** (`x11docker --gpu`) → hardware GL + `--ignore-gpu-blocklist`

Also prefer a large `--shm-size` (the launcher defaults to `3g`) so Chromium can
use `/dev/shm` instead of slow disk-backed shared memory. Resource capping with
x11docker `--limit` is **off by default** (enable with `LIMIT=1`) so software
rendering is not CPU-starved.

| Goal | How |
|------|-----|
| Best smoothness without host GPU | default software path; rebuild image after updating `run-chromium.sh` |
| GPU acceleration | `./run-x11docker.sh --gpu --home` |
| Force software GL | `CHROMIUM_GPU=0 ./run-x11docker.sh --home` |
| Cap CPU/RAM (~50%) | `LIMIT=1 ./run-x11docker.sh --home` |

Harmless noise in logs: missing D-Bus, GCM `DEPRECATED_ENDPOINT`, Vulkan
driver warnings without `--gpu`, `Failed to load cookie file from cookie`
(xclip), and WebRTC STUN `errorcode: -105` when a site cannot reach
`stun.l.google.com` / Cloudflare STUN.

If **file upload / Open File dialogs cancel on Enter or double-click** and
only a mouse click on **Open** works, that is Chromium, not the window
manager. Since 140 (Jan 2026, [crbug 470928605](https://issues.chromium.org/issues/470928605))
the GTK picker uses **Cancel as the default button** so a held Enter cannot
confirm a file a page pre-selected. GtkFileChooser also fires that default
on double-click, so both actions hit Cancel. The image LD_PRELOADs
`libchromium-filechooser-default.so` to put **Open** back as the default.
Keep Chromium's Cancel default with:

```bash
CHROMIUM_FILE_DIALOG_DEFAULT=cancel ./run-x11docker.sh --home
```

If **incognito starts failing after a few hours** while normal tabs still
work, look for `pthread_create: Resource temporarily unavailable (11)`.
Docker `--pids-limit` is cgroup `pids.max` and counts **threads**. Chromium
site isolation already uses many; an incognito window cannot reuse the
regular profile’s renderer processes, so it hits the cap first. Restart the
container, or raise the limit (default is now 4096):

```bash
PIDS_LIMIT=8192 ./run-x11docker.sh --home
```

If YouTube has **no sound** and you see ALSA `cannot find card '0'`, or x11docker
notes `pactl failed ... No such entity` / disables `--pulseaudio`, socket mode
failed (common on **PipeWire-Pulse**). The launcher defaults to
`--pulseaudio=tcp`. You should see `x11docker-chromium: enabling --pulseaudio=tcp`
at startup. Overrides: `PULSEAUDIO=host|socket|0`.

If the UI opens but **pages never load**, look for
`Network service crashed or was terminated` — that usually means the outer
seccomp profile is still missing a runtime I/O syscall (see
`preadv2`/`pwritev2` in `seccomp/chromium.json`). Sync the latest profile;
no image rebuild required for seccomp-only fixes.

### Optional features

| Goal | How |
|------|-----|
| GPU acceleration | `./run-x11docker.sh --gpu --home` |
| Sound | on by default as `--pulseaudio=tcp`; override with `PULSEAUDIO=host` / `socket` / `0` |
| Webcam | `./run-x11docker.sh --webcam --home` |
| Read-only rootfs | `READ_ONLY=1 ./run-x11docker.sh --home` |
| Extra Chromium args / URL | `./run-x11docker.sh --home -- https://example.com` |
| Emergency: disable Chromium sandbox | `CHROMIUM_NO_SANDBOX=1 ./run-x11docker.sh` (weaker; avoid) |

Example with GPU (sound is already on by default):

```bash
./run-x11docker.sh --gpu --home --share "$HOME/Downloads"
```

### Podman

```bash
x11docker --backend=podman --network --clipboard=c2h --home \
  -- \
  --shm-size=3g \
  --pids-limit=4096 \
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
4. **Resource limits** — `--pids-limit=4096` (cgroup `pids.max` counts threads, not just processes; 512 is too low for Chromium site isolation + incognito), large `--shm-size` (default `3g`). Optional x11docker CPU/RAM cap via `LIMIT=1`.
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

### “Did not receive PID of PID1”

That almost always means the **outer seccomp profile is missing syscalls x11docker’s PID1 needs**. x11docker does **not** use the image `ENTRYPOINT`; PID1 is `catatonit`/`tini` → `/bin/sh containerrc`. Required beyond Chromium’s own list:

- `fork` / `vfork` — Debian dash
- `signalfd` / `signalfd4` — catatonit/tini (`failed to create signalfd: Operation not permitted`)

```bash
grep -E '"fork"|"vfork"|"signalfd"' seccomp/chromium.json   # must match
./diagnose-startup.sh   # prints CONTAINERRC_OK, or Cannot fork / signalfd error
```

Rebuild alone does **not** fix this — update/sync `seccomp/chromium.json` on the host. Temporary diagnosis:

```bash
SECCOMP_PROFILE=unconfined ./run-x11docker.sh --home
```

## Why this exists

Browsers are high-risk software (JS, media codecs, extensions). Running them under x11docker gives a deployable, least-privilege GUI sandbox without sharing host display `:0` or using a full VM — and without the usual “just add `--no-sandbox`” footgun.

## Files

| File | Role |
|------|------|
| `Dockerfile` | Debian trixie + Chromium, GUI helpers, file-dialog LD_PRELOAD |
| `run-chromium.sh` | In-container Chromium launch (sandbox-aware) |
| `run-x11docker.sh` | Host launcher with seccomp + hardening flags |
| `gtk-modules/chromium-filechooser-default.c` | LD_PRELOAD: restore Open as GTK file-dialog default |
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
| `CHROMIUM_FILE_DIALOG_DEFAULT` | `open` | `open` restores Open as the GTK file-dialog default (Enter / double-click); `cancel` keeps Chromium's Cancel default |
| `KEYBOARD_LAYOUT` | host `XKBLAYOUT` or `us` | `setxkbmap` layout (auto-detected) |
| `XKB_OPTIONS` | `lv3:ralt_switch` | `setxkbmap -option` value |
| `SECCOMP_PROFILE` | `./seccomp/chromium.json` | Override seccomp path |
| `X11DOCKER_CHROMIUM_IMAGE` | `chromium` | Image name |
| `SHM_SIZE` | `3g` | Docker `/dev/shm` size |
| `PIDS_LIMIT` | `4096` | Max tasks (processes+threads) in the container |
| `LIMIT` | `0` | `1` enables x11docker `--limit` (CPU/RAM ~50%) |
| `READ_ONLY` | `0` | `1` enables read-only root + tmpfs |
| `DEBUG` | `0` | `1` traces the launcher |

## To do

- Trim packages further if a smaller image is needed.
- Optional Chromium enterprise policy pack for tighter web features.
