#!/bin/bash
# Patch the Proton launcher script to copy the extra dlls into the prefix.
# (from LukasPAH/GDK-Proton-Custom)
#
# Usage: patch_proton.sh <path to the proton script>
# The block goes right before `if use_wined3d:` in prefix setup, which both
# GE-Proton and Proton-CachyOS (Valve's script) have.

set -euo pipefail

FILE="${1:?usage: patch_proton.sh <path to proton script>}"

if ! grep -qE '^ +if use_wined3d:' "$FILE"; then
    echo "error: no 'if use_wined3d:' anchor in $FILE - Proton's script changed" >&2
    exit 1
fi

# Skip if already patched
if grep -q 'libasprintf-0.dll' "$FILE"; then
    echo "Proton is already patched."
    exit 0
fi

BLOCK=$(cat <<'EOF'
                dll_files = [
                    ("libasprintf-0.dll", "libasprintf-0.dll"),
                    ("libbrotlicommon.dll", "libbrotlicommon.dll"),
                    ("libbrotlidec.dll", "libbrotlidec.dll"),
                    ("libcares-2.dll", "libcares-2.dll"),
                    ("libcharset-1.dll", "libcharset-1.dll"),
                    ("libcrypto-3-x64.dll", "libcrypto-3-x64.dll"),
                    ("libiconv-2.dll", "libiconv-2.dll"),
                    ("libidn2-0.dll", "libidn2-0.dll"),
                    ("libintl-8.dll", "libintl-8.dll"),
                    ("libnghttp2-14.dll", "libnghttp2-14.dll"),
                    ("libnghttp3-9.dll", "libnghttp3-9.dll"),
                    ("libngtcp2_crypto_gnutls-8.dll", "libngtcp2_crypto_gnutls-8.dll"),
                    ("libngtcp2_crypto_ossl.dll", "libngtcp2_crypto_ossl.dll"),
                    ("libngtcp2_crypto_ossl-0.dll", "libngtcp2_crypto_ossl-0.dll"),
                    ("libngtcp2-16.dll", "libngtcp2-16.dll"),
                    ("libpsl-5.dll", "libpsl-5.dll"),
                    ("libssh2-1.dll", "libssh2-1.dll"),
                    ("libssl-3-x64.dll", "libssl-3-x64.dll"),
                    ("libunistring-5.dll", "libunistring-5.dll"),
                    ("libzstd.dll", "libzstd.dll"),
                    ("zlib1.dll", "zlib1.dll"),
                    ("xgameruntime.dll", "xgameruntime.dll"),
                    ("xgameruntime.dll.threading", "xgameruntime.dll.threading"),
                    ("windows.ui.core.textinput.dll", "windows.ui.core.textinput.dll"),
                    ("windows.devices.enumeration.dll", "windows.devices.enumeration.dll"),
                    ("Microsoft.WindowsAppRuntime.Bootstrap.dll", "Microsoft.WindowsAppRuntime.Bootstrap.dll"),
                    ("XCurl.dll", "XCurl.dll")
                ]

                # Some entries are optional and not every build ships them
                # (xgameruntime.dll.threading is built separately from Xodus'
                # xgameruntime). try_copy() raises on a missing source,
                # which would abort prefix setup, so skip what is absent.
                for (src,tgt) in dll_files:
                    if not os.path.exists(g_proton.lib_dir + "wine/x86_64-windows/" + src):
                        continue
                    try_copy(g_proton.lib_dir + "wine/x86_64-windows/" + src, "drive_c/windows/system32",
                            prefix=self.prefix_dir, track_file=tracked_files, link_debug=True)

EOF
)

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

awk -v block="$BLOCK" '
    /^ +if use_wined3d:/ && !done {
        print block
        done = 1
    }
    { print }
' "$FILE" > "$TMP"

cat "$TMP" > "$FILE"
