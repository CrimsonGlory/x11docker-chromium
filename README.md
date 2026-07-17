# x11docker-chromium

Run [Chromium](https://www.chromium.org/) inside Docker with [x11docker](https://github.com/mviereck/x11docker) for a tightly isolated GUI browser sandbox.

Inspired by [x11docker-cursor](https://github.com/CrimsonGlory/x11docker-cursor).

## Host dependencies

- docker (or podman)
- [x11docker](https://github.com/mviereck/x11docker)
- An X server option supported by x11docker (e.g. Xephyr, nxagent, or image `x11docker/xserver`)

Optional on the host: `xclip` (clipboard helpers).

## Build

```bash
docker build -t chromium .
```

## Run

x11docker options depend on your needs. Chromium needs network access and benefits from a larger shared-memory size (default Docker `/dev/shm` is 64 MiB and often crashes browsers).

### Minimal

```bash
x11docker --network -- --shm-size=1g -- chromium
```

### Recommended (persistent profile, Downloads, clipboard)

```bash
x11docker --network --clipboard --home \
  --share "$HOME/Downloads" \
  -- --shm-size=1g -- chromium
```

`--home` stores the Chromium profile under `~/.local/share/x11docker/chromium` (or the path you set with `--home=DIR`).

### Keyboard layout

If AltGr / non-US layout matters, pass your host layout (same pattern as x11docker-cursor):

```bash
x11docker --network --home \
  -- --shm-size=1g \
  -e KEYBOARD_LAYOUT=$(grep XKBLAYOUT /etc/default/keyboard | sed 's/XKBLAYOUT=//g' | tr -d '"') \
  -- chromium
```

### Optional features

| Goal | x11docker / docker flags |
|------|---------------------------|
| GPU acceleration | `--gpu` |
| Sound | `--pulseaudio` (image includes `libpulse0`) |
| Webcam | `--webcam` |
| Resource limits | `--limit` |
| Extra Chromium args | Append after the image name, e.g. `chromium https://example.com` |

Example with GPU and sound:

```bash
x11docker --network --gpu --pulseaudio --home \
  -- --shm-size=1g -- chromium
```

### Podman

```bash
x11docker --backend=podman --network --home \
  -- --shm-size=1g -- chromium
```

## Security notes

- Isolation comes from **x11docker** (separate X server, dropped capabilities, non-root user).
- Inside the container Chromium runs with `--no-sandbox` / `--disable-setuid-sandbox` because x11docker’s capability drops break Chromium’s setuid sandbox. Treat the container as the sandbox (same approach as the official x11docker Chromium example).
- Prefer `--clipboard=c2h` (container → host only) over full bidirectional clipboard if isolation matters.
- Avoid `--hostdisplay` unless you accept much weaker X isolation.

## Why this exists

Browsers are high-risk software (JS, media codecs, extensions). Running them under x11docker gives a deployable, least-privilege GUI sandbox without sharing host display `:0` or using a full VM.

## Files

| File | Role |
|------|------|
| `Dockerfile` | Debian trixie + Chromium and GUI helpers |
| `run-chromium.sh` | Container-safe Chromium launch flags |

## To do

- Trim packages further if a smaller image is needed.
- Optional seccomp / chrome policy tuning for advanced setups.
