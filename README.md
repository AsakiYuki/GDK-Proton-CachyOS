# GDK-Proton-CachyOS

Builds of [Proton-CachyOS](https://github.com/CachyOS/proton-cachyos) for
Microsoft GDK games, mainly Minecraft Bedrock Edition. Each release is a stock
Proton-CachyOS release with these additions:

- **GDK runtime:** WineGDK's `xgameruntime.dll`, which includes XUser for the
  in-game Microsoft sign-in, plus the WinRT dlls it needs.
- **XThreading:** [Xodus](https://github.com/xodus-gaming/xgameruntime)'
  open-source implementation, installed as `xgameruntime.dll.threading`. No
  Microsoft binary ships.
- **Online support:** mingw-w64 runtime dlls (OpenSSL, curl as `XCurl.dll`,
  nghttp2/3, ngtcp2 and others) for Minecraft's online features.
- **Wayland window borders:** a rebuilt `winewayland.so`, so KDE, GNOME and
  niri draw the window decorations instead of Wine's own title bar.
- **Default prefix:** Proton-CachyOS exits when `files/share/default_pfx` is
  missing. This build recreates it instead.

## Downloads

Each [release](../../releases) has two archives:

| Archive | CPU |
| --- | --- |
| `GDK-Proton-<tag>-x86_64.tar.gz` | Any x86-64 CPU |
| `GDK-Proton-<tag>-x86_64_v3.tar.gz` | CPUs with AVX2 (Intel Haswell, AMD Zen 1 or newer) |

### Steam

Extract the archive into `~/.steam/root/compatibilitytools.d/` and restart
Steam. It appears as `GDK-Proton-<tag>`, and the v3 build has a `-x86_64_v3`
suffix. Both builds can be installed next to each other and next to a stock
Proton-CachyOS.

### BedrockOnLinux

[BedrockOnLinux](https://github.com/Wyze3306/BedrockOnLinux) downloads
GDK-Proton itself. To use this fork, set `GDK_PROTON_REPO` in
`bol/config.py` to `AsakiYuki/GDK-Proton-CachyOS`. Then make its downloader pick the
`-x86_64.tar.gz` or `-x86_64_v3.tar.gz` asset, because a release has two
archives.

## Minecraft online

OpenSSL only works in Proton-based Wine builds, such as this one. To get the
game online and signed in:

1. Download
   [mingw-w64-x86_64-curl](https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-curl-8.17.0-1-any.pkg.tar.zst)
   and extract it.
2. Rename `mingw64/bin/libcurl-4.dll` to `XCurl.dll`. Copy it into
   Minecraft's binaries folder, replacing the existing `XCurl.dll`.
3. Download <https://curl.se/ca/cacert.pem> and rename it to `ca-bundle.crt`.
4. Next to the binaries, create the folders `etc/ssl/certs` and move
   `ca-bundle.crt` into `certs`.

The result should look like this:

<img width="772" height="240" alt="Minecraft folder with XCurl.dll and etc/ssl/certs/ca-bundle.crt" src="https://github.com/user-attachments/assets/d6e27fc3-ecb4-46be-9448-800535bbc1b6" />

The game can then reach its servers, and XUser signs in to your Microsoft
account in-game.

## Building

The release workflow is `.github/workflows/release.yml`. Start it from the
Actions tab with `workflow_dispatch`. It takes two inputs:

- `cachyos_tag`: the Proton-CachyOS release to base the build on, for example
  `cachyos-11.0-20261015-slr`.
- `cachyos_arch`: `both` (the default), `x86_64` or `x86_64_v3`.

| Job | Script | Output |
| --- | --- | --- |
| `build-decoration-fix` | `scripts/fix-wayland-decoration.sh` | `winewayland.so` |
| `build-winegdk` | `scripts/collect-winegdk-dlls.sh` | WineGDK dlls |
| `build-xodus-xgameruntime` | `scripts/build-xodus-xgameruntime.sh` | `xgameruntime.dll.threading` |
| `package` (once per arch) | `scripts/build.sh` | `GDK-Proton-<tag>-<arch>.tar.gz` |
| `release` | none | GitHub release `GDK-Proton-<tag>` |

The first three jobs are cached on their script, the decoration job on its
patch as well, and they are shared by both arches.

The same steps can be run locally. First run these three scripts, in any
order:

```sh
scripts/fix-wayland-decoration.sh    # needs docker or podman (DOCKER=podman)
scripts/collect-winegdk-dlls.sh
scripts/build-xodus-xgameruntime.sh  # needs a recent mingw-w64 toolchain
```

Then build the package:

```sh
CACHYOS_TAG=cachyos-11.0-20261015-slr CACHYOS_ARCH=x86_64_v3 scripts/build.sh
```

`build.sh` downloads the Proton-CachyOS release and checks its SHA-512. Then
it:

- patches the `proton` script with `scripts/patch_proton.sh`;
- renames the tool in `compatibilitytool.vdf`;
- copies all the dlls into `files/lib/wine` and refreshes `default_pfx`;
- packs the result.

## How it works

### GDK component dlls

WineGDK has been archived and split into
[xodus-gaming/xgameruntime](https://github.com/xodus-gaming/xgameruntime) and
[xodus-gaming/wine](https://github.com/xodus-gaming/wine). Xodus'
xgameruntime only implements XThreading so far, and neither part has XUser.
Switching to them outright would lose the Microsoft sign-in, so the package
uses both:

- `collect-winegdk-dlls.sh` takes the WineGDK dlls from the build published
  by BedrockOnLinux (Weather-OS/WineGDK plus their patch set), pinned by
  SHA-256. Together with XUser it takes the WinRT dlls XUser and Minecraft
  rely on:
  - `windows.web`: JSON parsing. With Wine's stock copy, the game crashes in
    `ParseJsonObject`.
  - `windows.ui`
  - `gameinput`
  - `windows.storage`

  All of them are PE-only, so they load in Proton-CachyOS' Wine.
- That `xgameruntime.dll` hands XThreading to `xgameruntime.dll.threading`:
  it calls that dll's `QueryApiImpl` for `CLSID_XThreadingImpl`. This used to
  be Microsoft's native dll. `build-xodus-xgameruntime.sh` builds Xodus'
  xgameruntime from a pinned commit and installs it under that name. CI
  builds it in a Fedora container, because it needs C23 and newer WinRT
  headers than Ubuntu's mingw-w64 has.

Once Xodus implements XUser and the rest of the GDK, its xgameruntime can
replace WineGDK's.

### Wayland window decorations

Server-side decorations come from the `zxdg_decoration_manager_v1` protocol.
Proton-CachyOS' `winewayland` ignores that protocol below version 2, but KWin,
niri and other Smithay-based compositors only offer version 1. So Wine falls
back to drawing its own bare title bar
([proton-ge-custom#955](https://github.com/GloriousEggroll/proton-ge-custom/issues/955)).
`patches/winewayland-xdg-decoration-v1.patch` makes it bind the version the
compositor offers, up to 2.

A Wine driver's unix side must match the release's `win32u` exactly, so
`fix-wayland-decoration.sh` rebuilds only `winewayland.so`. It builds from:

- the `wine-cachyos` commit the release tag pins;
- inside the Steam Runtime SDK image named by the tag's `Makefile.in`;
- against the same `libxkbcommon` Proton ships.

The script stops if the patch no longer applies. In CI this job is optional:
if it fails, the package ships CachyOS' stock `winewayland.so`.

### Proton script patches

`patch_proton.sh` makes two changes to the `proton` script, and running it
again changes nothing:

- During prefix setup, it copies the extra dlls into each prefix's
  `system32`. Missing optional dlls are skipped. This part comes from
  [LukasPAH/GDK-Proton-Custom](https://github.com/LukasPAH/GDK-Proton-Custom).
- When `default_pfx` is missing, it creates it with `wineboot`, as GE-Proton
  does, instead of exiting.

## Credits

- [CachyOS/proton-cachyos](https://github.com/CachyOS/proton-cachyos): the base Proton build.
- [Weather-OS/WineGDK](https://github.com/Weather-OS/WineGDK) and
  [BedrockOnLinux](https://github.com/Wyze3306/BedrockOnLinux): the GDK dlls and XUser.
- [xodus-gaming/xgameruntime](https://github.com/xodus-gaming/xgameruntime): XThreading.
- [LukasPAH/GDK-Proton-Custom](https://github.com/LukasPAH/GDK-Proton-Custom): the original dll copy patch.
- [MSYS2](https://www.msys2.org/): the mingw-w64 runtime dlls.
