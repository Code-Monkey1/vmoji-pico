# The vmoji dev container: everything docs/getting-started.md installs, ready to use.
# The build context is the repo root, narrowed to what's needed by /.dockerignore.
FROM ubuntu:24.04

# scripts/doctor.sh uses this: the udev rule that flashing needs can only live on the host.
ENV VMOJI_DEVCONTAINER=1

# Keep the first four lines in step with docs/getting-started.md. The rest is container-only:
# xvfb for 3D/scripts/render-preview.sh, clangd so Zed doesn't download its own, curl and
# ca-certificates for Zed's server, and the libraries Qt loads to open a window.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git python3 \
    cmake ninja-build build-essential pkg-config \
    gcc-arm-none-eabi libnewlib-arm-none-eabi libstdc++-arm-none-eabi-newlib libusb-1.0-0-dev \
    python3-venv libxcb-cursor0 openscad \
    xvfb xauth clangd curl ca-certificates \
    libegl1 libgl1 libxkbcommon0 libxkbcommon-x11-0 libdbus-1-3 libfontconfig1 libglib2.0-0t64 \
    libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 \
    libxcb-shape0 libxcb-xinerama0 \
    && rm -rf /var/lib/apt/lists/*

# The image's own user has UID 1000, the usual first desktop user, so files in the shared repo
# keep their owner. dialout: the serial ports, whose nodes come from the host with the same group
# on Debian/Ubuntu.
#
# Deliberately no sudo: the host's /dev is bound in, and root in here could delete its nodes.
# The folders are for the named volumes in devcontainer.json: a new volume copies its owner from
# the folder it mounts over, so they belong to this user with no chown needed.
RUN usermod --append --groups dialout ubuntu \
    && install -d -o ubuntu -g ubuntu /workspaces/vmoji/vmoji/build \
        /workspaces/vmoji/build-host-tests /workspaces/vmoji/tools/dashboard/.venv

USER ubuntu

# Only these files, so this slow step reruns only when the versions or the scripts change.
COPY --chown=ubuntu vmoji/CMakeLists.txt /tmp/vmoji-setup/CMakeLists.txt
COPY --chown=ubuntu vmoji/scripts /tmp/vmoji-setup/scripts
RUN /tmp/vmoji-setup/scripts/setup-sdk.sh && rm -rf /tmp/vmoji-setup

# The known-good BOSL2 from docs/getting-started.md: its master can break the models.
RUN mkdir -p /home/ubuntu/.local/share/OpenSCAD/libraries/BOSL2 \
    && cd /home/ubuntu/.local/share/OpenSCAD/libraries/BOSL2 \
    && git init --quiet \
    && git fetch --quiet --depth 1 https://github.com/BelfrySCAD/BOSL2.git \
        fcfce7c763863d8e66d5f36a551d11129ec1a607 \
    && git -c advice.detachedHead=false checkout --quiet FETCH_HEAD

# Lets clangd ask the ARM compiler where its headers are. Without it, every firmware file reports
# 'stdio.h' file not found. Last, so changing it doesn't rebuild the slow steps above.
ENV CLANGD_FLAGS=--query-driver=/usr/bin/arm-none-eabi-*
