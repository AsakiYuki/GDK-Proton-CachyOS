#!/bin/bash
# Assembles the final GDK-Proton package:
#   stock Proton-CachyOS release + patched winewayland.so (Wayland decoration
#   fix, see scripts/fix-wayland-decoration.sh) + WineGDK component dlls
#   (see scripts/collect-winegdk-dlls.sh) + Xodus' xgameruntime as
#   xgameruntime.dll.threading (see scripts/build-xodus-xgameruntime.sh) +
#   small mingw-w64 runtime dlls (openssl/curl/zlib/... for Minecraft
#   Bedrock's online functionality).
#
# Expects build/decoration-fix/, build/winegdk-dlls/ and
# build/xodus-xgameruntime/ to already be populated (either by CI
# downloading those job artifacts, or by running the three scripts above
# locally first).
#
# Environment:
#   CACHYOS_TAG   Proton-CachyOS release tag (default cachyos-11.0-20261015-slr)
#   CACHYOS_ARCH  x86_64 (default, any x86-64 CPU) or x86_64_v3 (AVX2 CPUs)

set -euo pipefail

CACHYOS_TAG="${CACHYOS_TAG:-cachyos-11.0-20261015-slr}"
CACHYOS_ARCH="${CACHYOS_ARCH:-x86_64}"
case "$CACHYOS_ARCH" in
    x86_64|x86_64_v3) ;;
    *) echo "CACHYOS_ARCH must be x86_64 or x86_64_v3, not '$CACHYOS_ARCH'" >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

# cachyos-11.0-20261015-slr -> proton-cachyos-11.0-20261015-slr-x86_64
UPSTREAM_NAME="proton-${CACHYOS_TAG}-${CACHYOS_ARCH}"
UPSTREAM_URL="https://github.com/CachyOS/proton-cachyos/releases/download/${CACHYOS_TAG}/${UPSTREAM_NAME}"
# GDK-Proton-cachyos-11.0-20261015-slr (plus -x86_64_v3 for that build)
PKG_NAME="GDK-Proton-${CACHYOS_TAG}"
[ "$CACHYOS_ARCH" = "x86_64" ] || PKG_NAME="${PKG_NAME}-${CACHYOS_ARCH}"
PKG_DIR="build/${PKG_NAME}"
# GDK-Proton-cachyos-11.0-20261015-slr-x86_64.tar.gz / ...-x86_64_v3.tar.gz
TARBALL="GDK-Proton-${CACHYOS_TAG}-${CACHYOS_ARCH}.tar.gz"

# mingw-w64-x86_64 runtime dlls needed for Minecraft Bedrock's online/TLS support
brotli=('brotli-1.2.0-1' 'libbrotlicommon libbrotlidec')
cares=('c-ares-1.34.8-1' 'libcares-2')
curl=('curl-8.20.0-1' 'libcurl-4')
gettext=('gettext-runtime-1.0-1' 'libintl-8 libasprintf-0')
libiconv=('libiconv-1.19-1' 'libiconv-2 libcharset-1')
libidn2=('libidn2-2.3.8-4' 'libidn2-0')
libpsl=('libpsl-0.21.5-3' 'libpsl-5')
libssh2=('libssh2-1.11.1-2' 'libssh2-1')
libunistring=('libunistring-1.4.2-1' 'libunistring-5')
nghttp2=('nghttp2-1.69.0-1' 'libnghttp2-14')
nghttp3=('nghttp3-1.9.0-1' 'libnghttp3-9')
ngtcp2=('ngtcp2-1.22.1-1' 'libngtcp2-16 libngtcp2_crypto_ossl-0 libngtcp2_crypto_gnutls-8')
openssl=('openssl-3.6.2-2' 'libcrypto-3-x64 libssl-3-x64')
zlib=('zlib-1.3.2-2' 'zlib1')
zstd=('zstd-1.5.7-2' 'libzstd')

packages=(brotli cares curl gettext libiconv libidn2 libpsl libssh2 libunistring nghttp2 nghttp3 ngtcp2 openssl zlib zstd)

mkdir -p build/extra
pushd build/extra >/dev/null

for package in "${packages[@]}"; do
    declare -n pkg="$package"
    pkgname="${pkg[0]}"
    [ "$package" = "cares" ] && pkgname_dir="c-ares" || pkgname_dir="$pkgname"
    echo "Downloading ${pkgname}..."
    curl -fsSL "https://repo.msys2.org/mingw/mingw64/mingw-w64-x86_64-${pkgname}-any.pkg.tar.zst" \
        | tar --zstd -x $(echo "${pkg[1]}" | xargs printf -- 'mingw64/bin/%s.dll ') --transform "s/mingw64\/bin\///"
done

cp -f libngtcp2_crypto_ossl-0.dll libngtcp2_crypto_ossl.dll
mv -f libcurl-4.dll XCurl.dll

popd >/dev/null

echo "Downloading ${UPSTREAM_NAME}..."
curl -fsSL "${UPSTREAM_URL}.tar.xz" -o "build/${UPSTREAM_NAME}.tar.xz"
curl -fsSL "${UPSTREAM_URL}.sha512sum" -o "build/${UPSTREAM_NAME}.sha512sum"
(cd build && sha512sum -c "${UPSTREAM_NAME}.sha512sum")
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR"
tar -xJf "build/${UPSTREAM_NAME}.tar.xz" -C "$PKG_DIR" --strip-components=1
rm -f "build/${UPSTREAM_NAME}.tar.xz" "build/${UPSTREAM_NAME}.sha512sum"

"$SCRIPT_DIR/patch_proton.sh" "$PKG_DIR/proton"

# Register under our own name, so Steam lists it next to (not in place of)
# a stock Proton-CachyOS install.
sed -i -E \
    -e "s|^([[:space:]]*)\"${UPSTREAM_NAME}\"([[:space:]]*//.*)?$|\\1\"${PKG_NAME}\"\\2|" \
    -e "s|(\"display_name\"[[:space:]]*)\"[^\"]*\"|\\1\"${PKG_NAME}\"|" \
    "$PKG_DIR/compatibilitytool.vdf"
grep -q "\"${PKG_NAME}\"" "$PKG_DIR/compatibilitytool.vdf" \
    || { echo "could not rename the tool in compatibilitytool.vdf" >&2; exit 1; }

DEST="$PKG_DIR/files/lib/wine/x86_64-windows"
DEST_UNIX="$PKG_DIR/files/lib/wine/x86_64-unix"

[ -n "$(ls -A build/winegdk-dlls 2>/dev/null)" ] \
    || echo "warning: build/winegdk-dlls is empty - package will be missing GDK component dlls (xgameruntime etc.)" >&2
[ -f build/xodus-xgameruntime/xgameruntime.dll.threading ] \
    || echo "warning: build/xodus-xgameruntime is empty - XThreading will fall back to WineGDK's own implementation" >&2

# Proton-CachyOS refuses to start without default_pfx (patch_proton.sh only
# recreates a deleted one), so keep it, with the overlaid dlls in it: most of
# its system32 dlls are links to the lib/wine copies, so they follow the
# copy into $DEST; real copies are refreshed so new prefixes start from them.
DEFAULT_SYS32="$PKG_DIR/files/share/default_pfx/drive_c/windows/system32"
[ -d "$DEFAULT_SYS32" ] \
    || echo "warning: $DEFAULT_SYS32 not found - it will be created on first launch" >&2

shopt -s nullglob
for src in build/extra/*.dll build/winegdk-dlls/* \
           build/xodus-xgameruntime/xgameruntime.dll.threading; do
    [ -f "$src" ] || continue
    name="$(basename "$src")"
    cp -f "$src" "$DEST/$name"
    if [ -f "$DEFAULT_SYS32/$name" ] && ! [ "$DEST/$name" -ef "$DEFAULT_SYS32/$name" ]; then
        cp -f "$src" "$DEFAULT_SYS32/$name"
    fi
done
shopt -u nullglob

if [ -f build/decoration-fix/winewayland.so ]; then
    cp -f build/decoration-fix/winewayland.so "$DEST_UNIX/winewayland.so"
else
    echo "warning: build/decoration-fix is incomplete - shipping stock (unfixed) winewayland.so" >&2
fi

# Existing prefixes get a wineboot update when wine.inf is newer than them.
touch "$PKG_DIR/files/share/wine/wine.inf"

# Name the tree rather than ".", so the archive has no bare "./" entry
# (BedrockOnLinux's extractor rejects it as an unsafe path).
tar -czf "$TARBALL" -C build "$PKG_NAME"
rm -rf "$PKG_DIR"

echo "Built $TARBALL"
