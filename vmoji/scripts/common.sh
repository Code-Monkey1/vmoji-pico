# Shared by the firmware scripts (sourced, not run). Expects the caller to have cd'd to vmoji/.
#
# Versions come from vmoji/CMakeLists.txt, the one place they are set (the Pico VS Code
# extension reads the same lines), so scripts and IDE never disagree.

cmake_var() {
    sed -n "s/^set($1 \(.*\))\$/\1/p" CMakeLists.txt | head -1
}

SDK_VERSION="$(cmake_var sdkVersion)"
PICOTOOL_VERSION="$(cmake_var picotoolVersion)"
# Same layout as the VS Code extension, so both can share one SDK checkout.
SDK_DIR="${PICO_SDK_PATH:-$HOME/.pico-sdk/sdk/$SDK_VERSION}"
# When the Pico VS Code extension is installed, CMakeLists.txt includes its hook, which
# forces the extension's SDK and toolchain: PICO_SDK_PATH then has no effect. Follow suit.
VSCODE_HOOK="$HOME/.pico-sdk/cmake/pico-vscode.cmake"
if [ -f "$VSCODE_HOOK" ]; then
    if [ -n "${PICO_SDK_PATH:-}" ] && [ "$PICO_SDK_PATH" != "$HOME/.pico-sdk/sdk/$SDK_VERSION" ]; then
        echo "note: PICO_SDK_PATH is ignored while the VS Code extension's $VSCODE_HOOK exists." >&2
    fi
    SDK_DIR="$HOME/.pico-sdk/sdk/$SDK_VERSION"
fi
# Override to build elsewhere (e.g. CI, tests). A relative path is relative to vmoji/.
BUILD_DIR="${VMOJI_BUILD_DIR:-build}"
case "$BUILD_DIR" in
    "" | . | .. | / | ./ | ../)
        echo "Refusing VMOJI_BUILD_DIR='$BUILD_DIR': it must be a dedicated build folder." >&2
        exit 1
        ;;
esac
UF2="$BUILD_DIR/vmoji.uf2"
# For messages: relative to the repo root unless the build dir was given as an absolute path.
case "$BUILD_DIR" in
    /*) BUILD_SHOWN="$BUILD_DIR" ;;
    *) BUILD_SHOWN="vmoji/$BUILD_DIR" ;;
esac
UF2_SHOWN="$BUILD_SHOWN/vmoji.uf2"

if [ -z "$SDK_VERSION" ]; then
    echo "Could not read sdkVersion from vmoji/CMakeLists.txt" >&2
    exit 1
fi
