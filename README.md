# GDK-Proton
This repository aims to share builds of GE-Proton, custom built with WineGDK and several extra components.
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

Now if you launch the game, the game should be able to phone home and get online. Just keep in mind that `XUser` is still not implemented so no Microsoft Account login yet.   

## Building

`.github/workflows/release.yml` builds and publishes a release from a GitHub
Actions `workflow_dispatch` run (set the `proton_version` input, e.g.
`Proton11-12`). It runs three jobs: `build-decoration-fix`, `build-winegdk`,
then `package-and-release` which combines both outputs with GE-Proton and
the mingw-w64 runtime dlls (`scripts/build.sh`) and publishes a GitHub
Release.

To run the same steps locally: `scripts/fix-wayland-decoration.sh`, then
`scripts/collect-winegdk-dlls.sh`, then `scripts/build.sh`.

### GDK component dlls

`scripts/collect-winegdk-dlls.sh` takes the WineGDK dlls from the WineGDK
build published by [BedrockOnLinux](https://github.com/Wyze3306/BedrockOnLinux)
(Weather-OS/WineGDK plus their patch set), pinned by SHA-256. It carries
XUser, so Minecraft signs in to the Microsoft account in-game, together with
the WinRT dlls it depends on (`windows.web` JSON, `windows.ui`, `gameinput`,
`windows.storage`). All are PE-only and load in GE-Proton's Wine. Microsoft's
native `xgameruntime.dll.threading` (used for XThreading; WineGDK's fallback
crashes the game) comes from Weather-OS/GDK-Proton `release10-32`, also
pinned. The `WineGDK` submodule is no longer used by the build.

### Wayland window decoration fix

Running under a Wayland compositor that only offers `zxdg_decoration_manager_v1`
version 1 (niri and other Smithay-based compositors) makes Wine fall back to
its own bare title bar instead of server-side decorations - this is
[proton-ge-custom#955](https://github.com/GloriousEggroll/proton-ge-custom/issues/955),
fixed upstream on `master` but not yet in a tagged GE-Proton release.
`scripts/fix-wayland-decoration.sh` rebuilds just `winewayland.drv` with that
fix cherry-picked onto the release tag, instead of waiting for the next
GE-Proton release or doing a full Proton rebuild.

### Known issues (WIP)

- `scripts/fix-wayland-decoration.sh`: building `winewayland.drv` through
  proton-ge-custom's own `make module=...` target pulls in its full
  optional-component dependency graph (ffmpeg/kaldi/vosk/piper/vkd3d/openxr),
  and `piper`'s onnxruntime fetch currently fails in a clean checkout. The
  script documents a direct-wine-configure workaround that gets further but
  still hits an upstream `make_vulkan`/`vk.xml` incompatibility when
  generating `include/wine/vulkan.h`.

This needs more upstream investigation before the decoration fix builds
reliably end-to-end.
