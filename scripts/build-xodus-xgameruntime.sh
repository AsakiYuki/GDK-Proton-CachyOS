#!/bin/bash
# Builds Xodus' open-source xgameruntime.dll (xodus-gaming/xgameruntime, the
# successor of WineGDK's xgameruntime) and installs it as
# build/xodus-xgameruntime/xgameruntime.dll.threading.
#
# Why under that name: the WineGDK xgameruntime.dll we ship (see
# scripts/collect-winegdk-dlls.sh) still carries XUser and the rest of the
# GDK, but hands XThreading off to a separate dll: it LoadLibrary()s
# "xgameruntime.dll.threading" and asks its QueryApiImpl for
# CLSID_XThreadingImpl (073b7dcb-1fcf-4030-94be-e3c9eb623428). That used to
# be Microsoft's own native xgameruntime.dll. Xodus' dll exports the same
# QueryApiImpl and implements exactly that class (XThreading is all it
# implements so far), so it drops in there and replaces the Microsoft binary.
# Once Xodus implements XUser and the rest, it can replace WineGDK's
# xgameruntime.dll outright.
#
# Requires: git, cmake, ninja, x86_64-w64-mingw32-gcc/g++ and a widl
# (Debian/Ubuntu: cmake ninja-build mingw-w64 mingw-w64-tools).

set -euo pipefail

# Pinned so a given script hash always builds the same dll (CI caches on it).
XODUS_REPO="https://github.com/xodus-gaming/xgameruntime.git"
XODUS_COMMIT="642e41c7617310c5d1b39d4e525b01ecae261f9e"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$ROOT_DIR/build/xodus-xgameruntime-src"
BUILD_DIR="$ROOT_DIR/build/xodus-xgameruntime-build"
OUT_DIR="$ROOT_DIR/build/xodus-xgameruntime"

if [ ! -d "$SRC_DIR/.git" ]; then
    git init -q "$SRC_DIR"
    git -C "$SRC_DIR" remote add origin "$XODUS_REPO"
fi
if [ "$(git -C "$SRC_DIR" rev-parse -q --verify HEAD 2>/dev/null)" != "$XODUS_COMMIT" ]; then
    echo "Fetching xodus-gaming/xgameruntime@${XODUS_COMMIT:0:12}..."
    git -C "$SRC_DIR" fetch -q --depth 1 origin "$XODUS_COMMIT"
    git -C "$SRC_DIR" checkout -q --detach FETCH_HEAD
fi
# Only googletest is a submodule, and tests stay off, so none are needed.

echo "Building xgameruntime.dll..."
rm -rf "$BUILD_DIR"
cmake -S "$SRC_DIR" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$SRC_DIR/win64-target.cmake" \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_TESTS=OFF
cmake --build "$BUILD_DIR" --parallel

DLL="$BUILD_DIR/bin/xgameruntime.dll"
[ -f "$DLL" ] || { echo "build did not produce $DLL" >&2; exit 1; }

# It is linked -static, so it must not pull in mingw runtime dlls that the
# prefix does not have.
if command -v x86_64-w64-mingw32-objdump >/dev/null 2>&1; then
    bad="$(x86_64-w64-mingw32-objdump -p "$DLL" | awk '/DLL Name:/ {print $3}' \
        | grep -iE '^(libstdc\+\+|libgcc|libwinpthread)' || true)"
    if [ -n "$bad" ]; then
        echo "xgameruntime.dll depends on mingw runtime dlls: $bad" >&2
        exit 1
    fi
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
x86_64-w64-mingw32-strip -o "$OUT_DIR/xgameruntime.dll.threading" "$DLL" 2>/dev/null \
    || cp -f "$DLL" "$OUT_DIR/xgameruntime.dll.threading"
echo "$XODUS_COMMIT" > "$OUT_DIR/xodus-xgameruntime.commit"

echo "Built $OUT_DIR/xgameruntime.dll.threading (xodus-gaming/xgameruntime@${XODUS_COMMIT:0:12})"
