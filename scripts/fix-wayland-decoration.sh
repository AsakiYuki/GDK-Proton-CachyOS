#!/bin/bash
# Rebuilds winewayland.drv against the exact wine commit used by a given
# GE-Proton release, with the upstream fix for proton-ge-custom#955 applied
# (zxdg_decoration_manager_v1 was only bound at version 2, so compositors
# that only offer version 1 - niri and other Smithay-based compositors -
# never got server-side decorations and fell back to Wine's bare title bar).
#
# The fix landed on proton-ge-custom's master branch (commit 52c97a2) after
# GE-Proton11-12 was tagged, so it isn't in the released tarball yet. This
# script registers just that one patch on the release tag, applies GE's full
# patch set (protonprep) so the build matches the released wine, and rebuilds
# only the winewayland.drv module (via `make module=winewayland.drv module`)
# instead of a full Proton build.
#
# Requires: git, docker (or podman), GNU make (nix-shell -p gnumake if absent).
#
# Output: build/decoration-fix/winewayland.drv.so (x86_64-unix)

set -euo pipefail

PROTON_VERSION="${PROTON_VERSION:-Proton11-12}"
GE_TAG="GE-${PROTON_VERSION}"
FIX_COMMIT="52c97a2d76856d1fe5df8dbdbf6984d5c4097d4a"
FIX_ISSUE="https://github.com/GloriousEggroll/proton-ge-custom/issues/955"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$ROOT_DIR/build/decoration-fix-src"
OUT_DIR="$ROOT_DIR/build/decoration-fix"

mkdir -p "$OUT_DIR"

if [ ! -d "$WORK_DIR" ]; then
    echo "Cloning proton-ge-custom at $GE_TAG..."
    git clone --depth 1 --branch "$GE_TAG" https://github.com/GloriousEggroll/proton-ge-custom.git "$WORK_DIR"
fi

cd "$WORK_DIR"

if git log -1 --format=%H | grep -q "$FIX_COMMIT"; then
    echo "Fix already present at HEAD, skipping cherry-pick."
elif grep -rq "winewayland-bind-xdg-decoration-manager-version-1" patches/ 2>/dev/null; then
    echo "Fix for #955 already present in this tag, skipping cherry-pick."
else
    # A plain cherry-pick conflicts because protonprep-valve-staging.sh's
    # apply_patch list diverged between the tag and master. The fix is just
    # one new patch file + one registration line, so apply those directly.
    echo "Fetching fix for $FIX_ISSUE..."
    git fetch --depth 1 origin "$FIX_COMMIT"
    PATCH_REL="patches/wine-hotfixes/pending/winewayland-bind-xdg-decoration-manager-version-1.patch"
    mkdir -p "$(dirname "$PATCH_REL")"
    git show "$FIX_COMMIT:$PATCH_REL" > "$PATCH_REL"

    PREP="patches/protonprep-valve-staging.sh"
    LAST_LINE="$(grep -n 'apply_patch "../patches/wine-hotfixes/pending/' "$PREP" | tail -1 | cut -d: -f1)"
    if [ -z "$LAST_LINE" ]; then
        echo "Could not find wine-hotfixes/pending apply_patch block in $PREP" >&2
        exit 1
    fi
    awk -v n="$LAST_LINE" -v p="../$PATCH_REL" '
        { print }
        NR == n {
            print "    # niri/Smithay offer xdg-decoration version 1, which got no server-side decorations (#955)"
            print "    apply_patch \"" p "\""
        }' "$PREP" > "$PREP.new"
    chmod --reference="$PREP" "$PREP.new"
    mv "$PREP.new" "$PREP"
    echo "Registered $PATCH_REL in $PREP after line $LAST_LINE."
fi

echo "Initializing wine submodules..."
git submodule update --init --recursive --depth 1

# The wine submodule is plain Valve wine; GE's release is that tree plus the
# patch set applied by protonprep, which among other things bumps
# WINE_GDI_DRIVER_VERSION (108 -> 111 for GE-Proton11-12). Building the
# module without it produces a driver the release's win32u rejects
# ("__wine_set_user_driver version mismatch"), leaving Wine with no display
# driver under PROTON_USE_WAYLAND=1. protonprep resets each submodule before
# patching, so it is safe to rerun on an existing work tree.
echo "Applying GE patch set (protonprep-valve-staging.sh)..."
./patches/protonprep-valve-staging.sh > "$OUT_DIR/protonprep.log" 2>&1 || {
    tail -n 50 "$OUT_DIR/protonprep.log" >&2
    echo "protonprep-valve-staging.sh failed" >&2
    exit 1
}
# apply_patch does not stop on a rejected patch, so check the log instead.
if grep -nE "FAILED|can't find file to patch|malformed patch|Reversed \(or previously applied\) patch detected" "$OUT_DIR/protonprep.log" >&2; then
    echo "GE patch set did not apply cleanly (see $OUT_DIR/protonprep.log)" >&2
    exit 1
fi
echo "Wine GDI driver version: $(grep -m1 -o 'WINE_GDI_DRIVER_VERSION [0-9]*' wine/include/wine/gdi_driver.h)"

MAKE_BIN="make"
if ! command -v make >/dev/null 2>&1; then
    echo "GNU make not found on PATH, using nix-shell -p gnumake."
    MAKE_BIN="nix-shell -p gnumake --run"
fi

# `make module=... module` waits on wine-configure, which by default first
# builds every WINE_DEPENDS entry: ffmpeg, openfst, kaldi, vosk, piper, openxr,
# vkd3d. winewayland.drv needs none of the speech/XR libs, and piper in
# particular fails in a clean checkout (its onnxruntime ExternalProject
# extracts to the wrong path). Command-line variables override Makefile.in's
# assignments and are forwarded into the SteamRT container via MAKEOVERRIDES,
# so trim the list to what wine's configure actually requires here:
#   ffmpeg            - WINE_AUTOCONF_ARGS passes --with-ffmpeg (hard error if missing)
#   libxml2/libxkbcommon - wayland driver (xkbcommon + xkbregistry)
#   libpcap           - kept to match the release configure
#   vkd3d             - VKD3D_PE_LIBS are hardcoded to its build output
MODULE_DEPS=(
    'WINE_DEPENDS=ffmpeg libxml2 libxkbcommon libpcap'
    'WINE_x86_64_DEPENDS=vkd3d'
    'WINE_aarch64_DEPENDS='
)
echo "Building winewayland.drv module (this pulls the SteamRT SDK container on first run)..."
if [ "$MAKE_BIN" = "make" ]; then
    make enable_ccache=0 "${MODULE_DEPS[@]}" module=winewayland.drv module
else
    nix-shell -p gnumake --run "make enable_ccache=0 $(printf '%q ' "${MODULE_DEPS[@]}") module=winewayland.drv module"
fi

# Wine 10+ names the unix side winewayland.so (older: winewayland.drv.so).
# The GE `module` rule copies only the unix lib into build/winewayland.drv/,
# so also look in the x86_64 object dir. The #955 fix only touches unix code,
# so the PE side is optional.
OBJ_DIR="build/build--local/obj-wine-x86_64/dlls/winewayland.drv"
SO_PATH=""
for f in build/winewayland.drv/lib/wine/x86_64-unix/winewayland.so \
         build/winewayland.drv/lib/wine/x86_64-unix/winewayland.drv.so \
         "$OBJ_DIR/winewayland.so" "$OBJ_DIR/winewayland.drv.so"; do
    if [ -e "$f" ]; then SO_PATH="$f"; break; fi
done
if [ -z "$SO_PATH" ]; then
    echo "Build did not produce winewayland.so / winewayland.drv.so" >&2
    exit 1
fi

rm -f "$OUT_DIR"/winewayland*
cp -f "$SO_PATH" "$OUT_DIR/$(basename "$SO_PATH")"
echo "Unix lib: $SO_PATH"

for f in build/winewayland.drv/lib/wine/x86_64-windows/winewayland.drv \
         "$OBJ_DIR/x86_64-windows/winewayland.drv" "$OBJ_DIR/winewayland.drv"; do
    if [ -f "$f" ]; then
        cp -f "$f" "$OUT_DIR/winewayland.drv"
        echo "PE dll: $f"
        break
    fi
done

echo "Fixed winewayland.drv built at $OUT_DIR"
