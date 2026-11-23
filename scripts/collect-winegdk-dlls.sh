#!/bin/bash
# Collects the WineGDK component dlls into build/winegdk-dlls/, for
# scripts/build.sh to overlay onto Proton-CachyOS.
#
# Source (pinned by SHA-256, so a changed upstream asset fails here): the
# WineGDK build published by BedrockOnLinux (Weather-OS/WineGDK commit
#   75637b67 + their winegdk-native5 patch set). It carries XUser, the
#   in-game Microsoft sign-in, which LukasPAH/WineGDK does not have, plus the
#   WinRT pieces XUser and Minecraft rely on: windows.web adds JsonArray and
#   the JsonObject/JsonValue parsing XUser's OAuth refresh uses (with the stock
#   copy the game crashes in ParseJsonObject), windows.ui adds CoreWindow,
#   gameinput adds mouse/pad readings, windows.storage the file picker.
#   All of these are PE-only (no unix side), so they load in any Wine 11.
#   The hash is WINEGDK_PREFIX_SHA256 in BedrockOnLinux's bol/config.py.
#
# WineGDK (archived) has since been split into xodus-gaming/xgameruntime and
# xodus-gaming/wine. Xodus' xgameruntime only implements XThreading so far,
# so it cannot replace this xgameruntime.dll (XUser would be lost). It does
# replace the dll this one hands XThreading to, xgameruntime.dll.threading,
# which used to be Microsoft's native binary: see
# scripts/build-xodus-xgameruntime.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$ROOT_DIR/build/winegdk-dlls"
WORK_DIR="$ROOT_DIR/build/winegdk-src"

WINEGDK_URL="https://github.com/Wyze3306/BedrockOnLinux/releases/download/winegdk-75637b674e1f-e5b3763a6037/winegdk-prefix-75637b674e1f-e5b3763a6037.tar.gz"
WINEGDK_SHA256="7c590b712430d67760c97258b8310d34e29a7293b2e05852bde866d1655eb994"
WINEGDK_DIR="prefix/lib/wine/x86_64-windows"

names=(
    xgameruntime
    wintypes
    twinapi.appcore
    windows.applicationmodel
    windows.ui.core.textinput
    windows.devices.enumeration
    windows.storage
    windows.storage.applicationdata
    windows.web
    windows.ui
    gameinput
)

fetch() {
    local url="$1" sha="$2" out="$3"
    if [ ! -f "$out" ] || ! echo "$sha  $out" | sha256sum -c --status -; then
        echo "Downloading $(basename "$out")..."
        curl -fsSL "$url" -o "$out.part"
        mv -f "$out.part" "$out"
    fi
    echo "$sha  $out" | sha256sum -c - >/dev/null || {
        echo "SHA-256 mismatch for $(basename "$out")" >&2
        exit 1
    }
}

mkdir -p "$WORK_DIR"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

fetch "$WINEGDK_URL" "$WINEGDK_SHA256" "$WORK_DIR/winegdk-prefix.tar.gz"

members=()
for name in "${names[@]}"; do
    members+=("$WINEGDK_DIR/$name.dll")
done
tar -xzf "$WORK_DIR/winegdk-prefix.tar.gz" -C "$OUT_DIR" \
    --strip-components=4 "${members[@]}"

for name in "${names[@]}"; do
    [ -f "$OUT_DIR/$name.dll" ] || { echo "missing $name.dll" >&2; exit 1; }
done

echo "Collected GDK dlls into $OUT_DIR:"
ls -1 "$OUT_DIR"
