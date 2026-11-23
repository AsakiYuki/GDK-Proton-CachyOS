# GDK-Proton
This repository aims to share builds of [Proton-CachyOS](https://github.com/CachyOS/proton-cachyos), custom built with WineGDK, [Xodus](https://github.com/xodus-gaming/xgameruntime)' open-source XThreading, and several extra components.
```
mingw-w64-x86_64-brotli
mingw-w64-x86_64-c-ares
mingw-w64-x86_64-ca-certificates
mingw-w64-x86_64-cc-libs
mingw-w64-x86_64-libidn2
mingw-w64-x86_64-libpsl
mingw-w64-x86_64-libssh2
mingw-w64-x86_64-nghttp2
mingw-w64-x86_64-nghttp3
mingw-w64-x86_64-ngtcp2
mingw-w64-x86_64-openssl
mingw-w64-x86_64-zlib
mingw-w64-x86_64-zstd
mingw-w64-x86_64-gettext-runtime
mingw-w64-x86_64-libiconv
mingw-w64-x86_64-libunistring
xgameruntime.dll.threading
```

## For Minecraft

**NOTES**: OpenSSL only works in protonified wine builds. You can use GDK-Proton (in the Releases section of this Repository) if you are not inclined to build proton from scratch yourself.   

To get online functionality working, you will need to follow this guide, exactly as mentioned:  
1) Download [mingw-w64-x86_64-curl](https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-curl-8.17.0-1-any.pkg.tar.zst) and extract it
2) In the extracted folder, rename `mingw64/bin/libcurl-4.dll` to `XCurl.dll`.
3) Copy it to Minecraft's binaries, replacing `XCurl.dll`.
4) Obtain SSL certificates from https://curl.se/ca/cacert.pem and rename this file to `ca-bundle.crt`
5) **IMPORTANT**, Create a folder named `etc`, and under that folder create another folder named `ssl`, and under the `ssl` folder, create a `certs` folder.
6) **IMPORTANT**, Move `ca-bundle.crt` to this new `certs` folder.
if you've done everything correctly, your file structure should look a bit like the following image:
<img width="772" height="240" alt="image" src="https://github.com/user-attachments/assets/d6e27fc3-ecb4-46be-9448-800535bbc1b6" />

Now if you launch the game, the game should be able to phone home and get online, and sign in to your Microsoft Account in-game (`XUser` comes from the WineGDK build described under [GDK component dlls](#gdk-component-dlls)).

## Building

`.github/workflows/release.yml` builds and publishes a release from a GitHub
Actions `workflow_dispatch` run. Inputs: `cachyos_tag` (a Proton-CachyOS
release tag, e.g. `cachyos-11.0-20261015-slr`) and `cachyos_arch` (`both`
by default; or only `x86_64`, for any CPU, or `x86_64_v3`, for AVX2 CPUs).
It runs `build-decoration-fix`, `build-winegdk` and
`build-xodus-xgameruntime` once, then `package` once per arch, which
overlays their outputs and the mingw-w64 runtime dlls onto that
Proton-CachyOS build (`scripts/build.sh`), and `release` publishes one
GitHub Release `GDK-Proton-<cachyos_tag>` with
`GDK-Proton-<cachyos_tag>-x86_64.tar.gz` and `...-x86_64_v3.tar.gz`. Each
registers in Steam under its own name (the v3 one with a `-x86_64_v3`
suffix), so they sit next to each other and to a stock Proton-CachyOS.

To run the same steps locally: `scripts/fix-wayland-decoration.sh`,
`scripts/collect-winegdk-dlls.sh` and `scripts/build-xodus-xgameruntime.sh`
(any order), then `scripts/build.sh`. Set `CACHYOS_TAG` / `CACHYOS_ARCH` to
build another release.

### GDK component dlls

WineGDK has been archived and split into
[xodus-gaming/xgameruntime](https://github.com/xodus-gaming/xgameruntime)
and [xodus-gaming/wine](https://github.com/xodus-gaming/wine). Xodus'
xgameruntime only implements XThreading so far (every other GDK class
returns `REGDB_E_CLASSNOTREG`), and Xodus Wine has no XUser either, so
switching to it outright would lose the Microsoft sign-in. The package uses
both, for now:

- `scripts/collect-winegdk-dlls.sh` takes the WineGDK dlls from the build
  published by [BedrockOnLinux](https://github.com/Wyze3306/BedrockOnLinux)
  (Weather-OS/WineGDK plus their patch set), pinned by SHA-256. It carries
  XUser, so Minecraft signs in to the Microsoft account in-game, together
  with the WinRT dlls it depends on (`windows.web` JSON, `windows.ui`,
  `gameinput`, `windows.storage`). All are PE-only and load in
  Proton-CachyOS' Wine.
- That `xgameruntime.dll` hands XThreading to a separate
  `xgameruntime.dll.threading` (it calls that dll's `QueryApiImpl` for
  `CLSID_XThreadingImpl`). This used to be Microsoft's native
  xgameruntime.dll, because WineGDK's own fallback crashes Minecraft.
  `scripts/build-xodus-xgameruntime.sh` now builds Xodus' xgameruntime from
  a pinned commit and installs it under that name instead, so no Microsoft
  binary ships. It needs a recent mingw-w64 (C23, newer WinRT headers); CI
  builds it in a Fedora container.

Once Xodus implements XUser and the rest of the GDK, its xgameruntime can
replace WineGDK's outright.

### Wayland window decoration fix

Running under a Wayland compositor that only offers `zxdg_decoration_manager_v1`
version 1 (KWin, niri and other Smithay-based compositors) makes Wine fall back to
its own bare title bar instead of server-side decorations
([proton-ge-custom#955](https://github.com/GloriousEggroll/proton-ge-custom/issues/955)).
Proton-CachyOS' wine still ignores the global below version 2.
`scripts/fix-wayland-decoration.sh` rebuilds just `winewayland.so` with
`patches/winewayland-xdg-decoration-v1.patch`, which binds the version the
compositor offers (at most 2). To match the release exactly, it
builds the `wine-cachyos` commit the release tag pins, inside the Steam
Runtime SDK image that tag's `Makefile.in` names, against the same
`libxkbcommon` submodule Proton ships. The job is optional: if it fails, the
package ships CachyOS' stock `winewayland.so`.
