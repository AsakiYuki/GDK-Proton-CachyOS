#!/bin/bash
# Pulls the GDK component DLLs out of a built WineGDK (nix build .#wine-gdk64)
# result tree into build/winegdk-dlls/, for scripts/build.sh to overlay onto
# GE-Proton.
#
# Note: WineGDK's include/Makefile.in lists windows.ui.text.core.idl twice,
# which makes `make install` fail with "not overwriting just created
# windows.ui.text.core.idl". The release workflow drops the duplicate line
# before `nix build`; do the same when building locally.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULT_LINK="$ROOT_DIR/build/winegdk-result"
OUT_DIR="$ROOT_DIR/build/winegdk-dlls"

mkdir -p "$OUT_DIR"

if [ ! -e "$RESULT_LINK" ]; then
    echo "Expected nix build result at $RESULT_LINK (run: nix build ./WineGDK#wine-gdk64 --out-link build/winegdk-result)" >&2
    exit 1
fi

names=(
    xgameruntime
    windows.ui.core.textinput
    windows.devices.enumeration
    windows.applicationmodel
    Microsoft.WindowsAppRuntime.Bootstrap
    wintypes
    twinapi.appcore
)

found_any=0
for name in "${names[@]}"; do
    hit="$(find "$RESULT_LINK/" -iname "${name}.dll" -print -quit)"
    if [ -n "$hit" ]; then
        cp -f "$hit" "$OUT_DIR/"
        found_any=1
    else
        echo "warning: ${name}.dll not found under $RESULT_LINK" >&2
    fi
    # xgameruntime ships a sibling .dll.threading data file next to the dll
    sibling="$(find "$RESULT_LINK/" -iname "${name}.dll.threading" -print -quit)"
    if [ -n "$sibling" ]; then
        cp -f "$sibling" "$OUT_DIR/"
    fi
done

if [ "$found_any" -eq 0 ]; then
    echo "No GDK dlls found under $RESULT_LINK - build likely failed before producing an install tree." >&2
    exit 1
fi

echo "Collected GDK dlls into $OUT_DIR"
