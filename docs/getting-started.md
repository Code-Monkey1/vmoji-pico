# Getting started

This sets up a Linux machine to work on every part of vmoji. The commands use `apt`
(Ubuntu, Debian, Linux Mint); other distributions need the equivalent packages. macOS and
Windows are untested.

You only need the parts you will work on:

| Part | Needs |
|------|-------|
| Firmware | CMake, Ninja, the ARM GCC toolchain, the Pico SDK, libusb (for flashing) |
| Dashboard | Python 3.10 or newer |
| 3D | OpenSCAD and the BOSL2 library |

## 1. System packages

```bash
sudo apt install git cmake ninja-build build-essential pkg-config \
    gcc-arm-none-eabi libnewlib-arm-none-eabi libusb-1.0-0-dev \
    python3 python3-venv libxcb-cursor0 \
    openscad
```

Drop the lines you don't need: line 2 is firmware, line 3 the dashboard, line 4 the 3D
part. `libusb-1.0-0-dev` lets the SDK build a `picotool` that can flash over USB.

## 2. Get the code

```bash
git clone <repository-url> vmoji-pico
cd vmoji-pico
```

## 3. Firmware: the Pico SDK

```bash
vmoji/scripts/setup-sdk.sh
```

This clones the SDK version pinned in [`vmoji/CMakeLists.txt`](../vmoji/CMakeLists.txt)
(`sdkVersion`) into `~/.pico-sdk/sdk/<version>`, the same place the Pico VS Code extension
uses. Set `PICO_SDK_PATH` to put it elsewhere (not possible with the extension installed,
see below). Then build and flash: [Firmware](firmware.md).

## 4. Dashboard: a Python virtual environment

```bash
cd tools/dashboard
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

`requirements.txt` includes the test and lint tools (pytest, ruff).

## 5. 3D: the BOSL2 library

Every part includes [BOSL2](https://github.com/BelfrySCAD/BOSL2). Install it into
OpenSCAD's library folder:

```bash
git clone https://github.com/BelfrySCAD/BOSL2.git ~/.local/share/OpenSCAD/libraries/BOSL2
```

The models are tested with OpenSCAD 2021.01, the version Ubuntu 24.04 ships. BOSL2 changes
over time; if a newer version breaks the models, check out an older BOSL2 commit (known
good: `fcfce7c7`, August 2026).

## 6. Access to the board over USB

Two one-time permission fixes, so nothing needs `sudo`:

```bash
# Flashing: let picotool reach the Pico.
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="2e8a", MODE="0666"' | \
    sudo tee /etc/udev/rules.d/99-picotool.rules
sudo udevadm control --reload-rules && sudo udevadm trigger

# Serial port (/dev/ttyACM0): join the dialout group, then log out and back in.
sudo usermod -aG dialout $USER
```

## 7. Check your setup

```bash
scripts/doctor.sh    # every prerequisite, with a fix for anything missing
scripts/check.sh     # build and run all the tests
```

`doctor.sh` exits with an error only for missing requirements; warnings (such as the
`dialout` group before you log back in) are worth fixing but don't block anything.
`check.sh` should end with "All checks passed.". If not, see
[Troubleshooting](troubleshooting.md).

## Optional: VS Code

The command line is all you need, but the
[Raspberry Pi Pico extension](https://marketplace.visualstudio.com/items?itemName=raspberry-pi.raspberry-pi-pico)
works too: open the **`vmoji/`** folder (not the repository root) as the workspace, since
its build settings live in `vmoji/.vscode`. The extension installs its own SDK, ARM
toolchain and picotool under `~/.pico-sdk`. Once it is installed, every build uses those
(the scripts and plain CMake too), and `PICO_SDK_PATH` has no effect. Ninja must still be
on your `PATH` for the scripts. The extension also adds debugging over SWD with a Raspberry
Pi Debug Probe.
