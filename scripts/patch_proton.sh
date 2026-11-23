#!/bin/bash
# Patches Proton-CachyOS' `proton` script (idempotent):
#
# 1. Copy the extra dlls into each prefix's system32 during prefix setup,
#    right before `if use_wined3d:` (from LukasPAH/GDK-Proton-Custom).
# 2. Recreate a missing files/share/default_pfx instead of exiting with
#    "Default prefix is missing, something is very wrong.", as GE-Proton
#    does. The script's own make_default_prefix() cannot be used: it takes a
#    `dist_lock` that Valve's script no longer defines.
# 3. When VKD3D_FRAME_RATE caps the game, present with FIFO (vsync). A
#    frame-rate limiter without vsync on a fixed-refresh display drifts
#    against the refresh: at 60 FPS on a 59.88 Hz panel, the presents cross
#    the vblank every ~8 s and for about a second frames are shown twice and
#    then dropped, so the game looks like 30 FPS while every overlay counts
#    60. BedrockOnLinux sets that cap whenever Minecraft has vsync off. The
#    frame latency drops from vkd3d-proton's default 3 to 2 as well, or the
#    FIFO queue stays full and the mouse lags ~3 refreshes behind (1 frame
#    misses a vblank on every CPU spike of the game). An
#    explicit VKD3D_SWAPCHAIN_PRESENT_MODE or VKD3D_SWAPCHAIN_LATENCY_FRAMES
#    wins; PROTON_ALLOW_TEARING=1 turns all of it off.
#
# Usage: patch_proton.sh <path to the proton script>

set -euo pipefail

FILE="${1:?usage: patch_proton.sh <path to proton script>}"

python3 -I - "$FILE" <<'PY'
import re
import sys
import textwrap

path = sys.argv[1]
with open(path) as f:
    text = f.read()

# Optional entries are skipped when absent (try_copy() raises on a missing
# source, which would abort prefix setup): xgameruntime.dll.threading is
# built separately from Xodus' xgameruntime.
DLLS = """
    libasprintf-0 libbrotlicommon libbrotlidec libcares-2 libcharset-1
    libcrypto-3-x64 libiconv-2 libidn2-0 libintl-8 libnghttp2-14 libnghttp3-9
    libngtcp2_crypto_gnutls-8 libngtcp2_crypto_ossl libngtcp2_crypto_ossl-0
    libngtcp2-16 libpsl-5 libssh2-1 libssl-3-x64 libunistring-5 libzstd zlib1
    xgameruntime windows.ui.core.textinput windows.devices.enumeration
    Microsoft.WindowsAppRuntime.Bootstrap XCurl
""".split()
names = [n + ".dll" for n in DLLS] + ["xgameruntime.dll.threading"]
name_list = textwrap.fill(", ".join(repr(n) for n in names), 100,
                          initial_indent=" " * 20, subsequent_indent=" " * 20)

COPY_MARK = "# GDK-Proton: extra dlls"
COPY = f"""\
                {COPY_MARK}
                for name in (
{name_list}):
                    src = g_proton.lib_dir + "wine/x86_64-windows/" + name
                    if os.path.exists(src):
                        try_copy(src, "drive_c/windows/system32",
                                prefix=self.prefix_dir, track_file=tracked_files, link_debug=True)

"""

MISSING = """\
        log("Default prefix is missing, something is very wrong.")
        sys.exit(1)
"""
CREATE = """\
        local_env = dict(g_session.env)
        local_env["WINEPREFIX"] = g_proton.default_pfx_dir
        local_env["WINEDEBUG"] = "-all"
        g_session.run_proc([g_proton.wine_bin, "wineboot"], local_env)
        g_session.run_proc([g_proton.wineserver_bin, "-w"], local_env)
"""

if COPY_MARK not in text:
    anchor = re.search(r"^ +if use_wined3d:", text, re.M)
    if not anchor:
        sys.exit(f"error: no 'if use_wined3d:' anchor in {path} - Proton's script changed")
    text = text[:anchor.start()] + COPY + text[anchor.start():]

FIFO_MARK = "# GDK-Proton: vsync with a frame limiter"
FIFO = f"""\
        {FIFO_MARK}
        if (self.env.get("VKD3D_FRAME_RATE", "").strip() not in ("", "0")
                and "VKD3D_SWAPCHAIN_PRESENT_MODE" not in self.env
                and self.env.get("PROTON_ALLOW_TEARING", "0") in ("", "0")):
            self.env["VKD3D_SWAPCHAIN_PRESENT_MODE"] = "FIFO"
            # vkd3d-proton lets the game run 3 frames ahead by default, and
            # with FIFO the queue stays full, so input waits ~3 refreshes.
            # 1 frame leaves no slack: every CPU spike of the game's main
            # thread misses a vblank (~1 per second on Minecraft). 2 does.
            self.env.setdefault("VKD3D_SWAPCHAIN_LATENCY_FRAMES", "2")
            log("GDK-Proton: VKD3D_FRAME_RATE is set, presenting with FIFO and "
                + self.env["VKD3D_SWAPCHAIN_LATENCY_FRAMES"] + " frame(s) of latency")

"""

if FIFO_MARK not in text:
    anchor = re.search(r"^        if \"WINE_HIDE_AMD_GPU\" not in self.env", text, re.M)
    if not anchor:
        sys.exit(f"error: no WINE_HIDE_AMD_GPU anchor in {path} - Proton's script changed")
    text = text[:anchor.start()] + FIFO + text[anchor.start():]

if CREATE not in text:
    if MISSING not in text:
        sys.exit(f"error: no default prefix check in {path} - Proton's script changed")
    text = text.replace(MISSING, CREATE)

with open(path, "w") as f:
    f.write(text)
print(f"Patched {path}")
PY
