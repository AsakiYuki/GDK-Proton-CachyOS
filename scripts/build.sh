#!/bin/bash
# Assembles the final GDK-Proton package:
#   stock GE-Proton release + patched winewayland.drv (Wayland decoration
#   fix, see scripts/fix-wayland-decoration.sh) + WineGDK component dlls
#   (see scripts/collect-winegdk-dlls.sh) + small mingw-w64 runtime dlls
#   (openssl/curl/zlib/... for Minecraft Bedrock's online functionality).
#
# Expects build/decoration-fix/ and build/winegdk-dlls/ to already be
# populated (either by CI downloading those job artifacts, or by running
# scripts/fix-wayland-decoration.sh and scripts/collect-winegdk-dlls.sh
# locally first).

set -euo pipefail

export PROTON_VERSION="${PROTON_VERSION:-Proton11-12}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

PROTON_RELEASE="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-${PROTON_VERSION}/GE-${PROTON_VERSION}-x86_64.tar.gz"

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

echo "Downloading GE-${PROTON_VERSION}..."
curl -fsSL "$PROTON_RELEASE" -o build/proton.tar.gz
rm -rf "build/GDK-${PROTON_VERSION}"
mkdir -p "build/GDK-${PROTON_VERSION}"
tar -xf build/proton.tar.gz -C "build/GDK-${PROTON_VERSION}" --strip-components=1
rm -f build/proton.tar.gz

pushd build >/dev/null
"$SCRIPT_DIR/patch_proton.sh"
popd >/dev/null

DEST="build/GDK-${PROTON_VERSION}/files/lib/wine/x86_64-windows"
DEST_UNIX="build/GDK-${PROTON_VERSION}/files/lib/wine/x86_64-unix"

cp -f build/extra/*.dll "$DEST/"

if [ -d build/winegdk-dlls ] && [ -n "$(ls -A build/winegdk-dlls 2>/dev/null)" ]; then
    cp -f build/winegdk-dlls/* "$DEST/"
else
    echo "warning: build/winegdk-dlls is empty - package will be missing GDK component dlls (xgameruntime etc.)" >&2
fi

# (Not `ls a b | head -1`: ls exits 2 when either is missing, which kills
# the script silently under pipefail.)
FIX_SO=""
for f in build/decoration-fix/winewayland.so build/decoration-fix/winewayland.drv.so; do
    if [ -e "$f" ]; then FIX_SO="$f"; break; fi
done
if [ -n "$FIX_SO" ]; then
    # Install under whichever unix lib name this Proton release ships.
    if [ -e "$DEST_UNIX/winewayland.so" ]; then
        cp -f "$FIX_SO" "$DEST_UNIX/winewayland.so"
    else
        cp -f "$FIX_SO" "$DEST_UNIX/winewayland.drv.so"
    fi
    if [ -f build/decoration-fix/winewayland.drv ]; then
        cp -f build/decoration-fix/winewayland.drv "$DEST/"
    fi
else
    echo "warning: build/decoration-fix is incomplete - shipping stock (unfixed) winewayland.drv" >&2
fi

# Force wine to refresh its bundled prefix so the new/replaced dlls get
# picked up on next first run.
touch "build/GDK-${PROTON_VERSION}/files/share/wine/wine.inf"
rm -rf "build/GDK-${PROTON_VERSION}/files/share/default_pfx"

mkdir -p build/proton-package
rm -rf "build/proton-package/GDK-${PROTON_VERSION}"
mv "build/GDK-${PROTON_VERSION}" "build/proton-package/GDK-${PROTON_VERSION}"
tar -czf "GDK-${PROTON_VERSION}-x86_64.tar.gz" -C "build/proton-package" .

echo "Built GDK-${PROTON_VERSION}-x86_64.tar.gz"
