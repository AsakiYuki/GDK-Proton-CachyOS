#!/bin/bash
# Rebuilds Proton-CachyOS' winewayland.so with
# patches/winewayland-xdg-decoration-v1.patch, the fix for
# proton-ge-custom#955: winewayland ignored zxdg_decoration_manager_v1 below
# version 2, so compositors that only offer version 1 (KWin, niri and other
# Smithay-based compositors) never got server-side decorations and Wine drew
# its own bare title bar. wine-cachyos still has the old code as of
# cachyos-11.0-20261015-slr.
#
# The unix side of a wine driver has to match the release's win32u/ntdll
# exactly (win32u rejects a WINE_GDI_DRIVER_VERSION mismatch), so this
# builds from the exact wine-cachyos commit the release tag pins as its
# `wine` submodule, inside the exact Steam Runtime SDK image the tag's
# Makefile.in builds with, and only builds dlls/winewayland.drv's unix lib
# (plus the tools and win32u/ntdll it links against). The fix is unix-only,
# so the release's PE winewayland.drv stays as is.
#
# Requires: git, curl, docker (or podman as DOCKER=podman).
#
# Output: build/decoration-fix/winewayland.so (x86_64-unix)

set -euo pipefail

CACHYOS_TAG="${CACHYOS_TAG:-cachyos-11.0-20261015-slr}"
DOCKER="${DOCKER:-docker}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$ROOT_DIR/build/decoration-fix-src"
OUT_DIR="$ROOT_DIR/build/decoration-fix"
WINE_SRC="$WORK_DIR/wine"
WINE_OBJ="$WORK_DIR/obj-wine-x86_64"

mkdir -p "$WORK_DIR" "$OUT_DIR"

# --- Resolve what the release tag was built from ---------------------------

PROTON_SRC="$WORK_DIR/proton-cachyos"
if [ ! -d "$PROTON_SRC/.git" ] || [ "$(git -C "$PROTON_SRC" describe --tags --exact-match 2>/dev/null)" != "$CACHYOS_TAG" ]; then
    rm -rf "$PROTON_SRC"
    echo "Cloning proton-cachyos at $CACHYOS_TAG (no submodules)..."
    git clone -q --depth 1 --branch "$CACHYOS_TAG" https://github.com/CachyOS/proton-cachyos.git "$PROTON_SRC"
fi

WINE_COMMIT="$(git -C "$PROTON_SRC" ls-tree HEAD wine | awk '{print $3}')"
WINE_URL="$(git -C "$PROTON_SRC" config -f .gitmodules submodule.wine.url)"
STEAMRT_IMAGE="$(sed -n 's/^[[:space:]]*STEAMRT_IMAGE ?= \(.*x86_64.*\)$/\1/p' "$PROTON_SRC/Makefile.in" | head -1)"
if [ -z "$WINE_COMMIT" ] || [ -z "$WINE_URL" ] || [ -z "$STEAMRT_IMAGE" ]; then
    echo "Could not read the wine submodule / STEAMRT_IMAGE from $CACHYOS_TAG" >&2
    exit 1
fi
echo "Wine: $WINE_URL @ $WINE_COMMIT"
echo "SDK image: $STEAMRT_IMAGE"

# The SDK's xkbcommon has no xkbregistry, which winewayland needs; Proton
# builds its own from this submodule (steamrtdeps/build-libxkbcommon.mk) and
# ships it in files/lib, so build the same one to compile against.
if [ ! -f "$PROTON_SRC/steamrtdeps/libxkbcommon/meson.build" ]; then
    echo "Fetching proton-cachyos' libxkbcommon submodule..."
    git -C "$PROTON_SRC" submodule update -q --init --depth 1 steamrtdeps/libxkbcommon
fi

# --- Fetch wine and apply the fix ------------------------------------------

if [ ! -d "$WINE_SRC/.git" ]; then
    git init -q "$WINE_SRC"
    git -C "$WINE_SRC" remote add origin "$WINE_URL"
fi
if [ "$(git -C "$WINE_SRC" rev-parse -q --verify HEAD 2>/dev/null)" != "$WINE_COMMIT" ]; then
    echo "Fetching wine-cachyos@${WINE_COMMIT:0:12}..."
    git -C "$WINE_SRC" fetch -q --depth 1 origin "$WINE_COMMIT"
    git -C "$WINE_SRC" checkout -q --detach -f FETCH_HEAD
    rm -rf "$WINE_OBJ"
fi
# Start from a clean file, so a rerun does not apply the patch twice.
git -C "$WINE_SRC" checkout -q -- dlls/winewayland.drv/wayland.c
PATCH="$ROOT_DIR/patches/winewayland-xdg-decoration-v1.patch"
if ! git -C "$WINE_SRC" apply "$PATCH"; then
    echo "error: $PATCH does not apply to wine-cachyos@${WINE_COMMIT:0:12}" >&2
    exit 1
fi
echo "Applied the #955 decoration fix:"
git -C "$WINE_SRC" diff -U1 dlls/winewayland.drv/wayland.c
echo "Wine GDI driver version: $(grep -m1 -o 'WINE_GDI_DRIVER_VERSION [0-9]*' "$WINE_SRC/include/wine/gdi_driver.h")"

# --- Build only the unix lib, inside the release's SDK image ---------------

echo "Building winewayland.so in the Steam Runtime SDK (pulls the image on first run)..."
mkdir -p "$WINE_OBJ"
"$DOCKER" run --rm \
    -u "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -e XDG_CACHE_HOME=/obj/.cache \
    -v "$WINE_SRC:/src" \
    -v "$WINE_OBJ:/obj" \
    -v "$PROTON_SRC:/proton:ro" \
    -w /obj \
    "$STEAMRT_IMAGE" \
    bash -euo pipefail -c '
        # The wine-cachyos git tree has no (or stale) generated files;
        # prepare it the way Proton'"'"'s Makefile.in does (.wine-post-source,
        # rules-wine-requests, rules-autoconf): its wine patches, then the
        # vulkan headers/thunks, syscall tables, server protocol headers and
        # configure script.
        if [ ! -f /obj/.source-prepared ]; then
            if [ -d /proton/patches/wine ]; then
                for p in $(find /proton/patches/wine -name "*.patch" | sort); do
                    patch -d /src -Np1 -i "$p"
                done
            fi
            (cd /src && dlls/winevulkan/make_vulkan -x vk.xml -X video.xml)
            (cd /src && tools/make_specfiles) || true
            # server_protocol.h & co in git lag behind protocol.def
            # (rules-wine-requests.mk regenerates them too).
            (cd /src && tools/make_requests)
            (cd /src && autoreconf -fi)
            touch /obj/.source-prepared
        fi
        if [ ! -f /obj/deps/.xkbcommon-built ]; then
            rm -rf /obj/deps /obj/xkbcommon-build
            meson setup /obj/xkbcommon-build /proton/steamrtdeps/libxkbcommon \
                --prefix=/obj/deps --libdir=lib --buildtype=release \
                -Denable-xkbregistry=true -Denable-docs=false -Denable-x11=false \
                -Denable-bash-completion=false -Denable-wayland=false \
                -Denable-tools=false
            ninja -C /obj/xkbcommon-build install
            touch /obj/deps/.xkbcommon-built
        fi
        export PKG_CONFIG_PATH=/obj/deps/lib/pkgconfig
        if [ ! -f Makefile ]; then
            # Same base flags as the release; only x86_64 is needed since
            # the PE side is not rebuilt.
            /src/configure \
                --enable-win64 --enable-archs=x86_64 \
                --enable-build-id --disable-tests \
                --with-wayland --without-x --without-oss \
                CFLAGS="-O2 -g -Wno-stringop-overflow -Wno-incompatible-pointer-types"
        fi
        # The release links libwayland-egl and libxkbregistry; without them
        # the driver would build but differ from (and lack features of) it.
        for v in WAYLAND_CLIENT_LIBS WAYLAND_EGL_LIBS XKBCOMMON_LIBS XKBREGISTRY_LIBS; do
            grep -qE "^$v *=.*-l" Makefile || { echo "configure did not find $v" >&2; exit 1; }
        done
        make -j"$(nproc)" dlls/winewayland.drv/winewayland.so
        # The release ships its unix libs stripped, too.
        strip --strip-unneeded -o /obj/winewayland.so dlls/winewayland.drv/winewayland.so
    '

SO_PATH="$WINE_OBJ/winewayland.so"
[ -f "$SO_PATH" ] || { echo "Build did not produce $SO_PATH" >&2; exit 1; }

# A driver built against different libs than the release's would fail to
# load (or silently lose features), so its NEEDED list must match.
if command -v readelf >/dev/null 2>&1; then
    echo "NEEDED: $(readelf -d "$SO_PATH" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | tr '\n' ' ')"
fi

rm -f "$OUT_DIR"/winewayland*
cp -f "$SO_PATH" "$OUT_DIR/winewayland.so"
cat > "$OUT_DIR/decoration-fix.info" <<EOF
cachyos_tag=$CACHYOS_TAG
wine_commit=$WINE_COMMIT
steamrt_image=$STEAMRT_IMAGE
EOF

echo "Fixed winewayland.so built at $OUT_DIR"
