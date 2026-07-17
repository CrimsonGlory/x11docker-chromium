FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

# Chromium + libs and helpers useful under x11docker
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    chromium \
    fonts-liberation \
    fonts-noto-color-emoji \
    hicolor-icon-theme \
    libcanberra-gtk3-module \
    libegl1 \
    libgbm1 \
    libgl1 \
    libpulse0 \
    # sudo for optional x11docker --sudouser
    sudo \
    xauth \
    xclip \
    # keyboard / maximize helpers (same motivation as x11docker-cursor)
    xkb-data \
    x11-xkb-utils \
    x11-xserver-utils \
    xdg-utils \
    && rm -rf /var/lib/apt/lists/*

# Optional localization package if present on this Debian release
RUN apt-get update \
    && apt-get install -y --no-install-recommends chromium-l10n \
    || true \
    && rm -rf /var/lib/apt/lists/*

COPY run-chromium.sh /usr/local/bin/run-chromium.sh
RUN chmod +x /usr/local/bin/run-chromium.sh

# Do not set USER: x11docker creates a host-like unprivileged user.

CMD ["/usr/local/bin/run-chromium.sh"]
