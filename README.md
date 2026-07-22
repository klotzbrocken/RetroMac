# RetroMac

**Turn your Mac into a retro computer.** RetroMac is a macOS menu-bar app that lays a
real-time CRT/retro shader over your screen and dresses the desktop up as the machines we
grew up with, from Mac OS 9 to Windows XP to BeOS.

[![Latest release](https://img.shields.io/github/v/release/klotzbrocken/RetroMac?label=release)](https://github.com/klotzbrocken/RetroMac/releases)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](https://myretromac.app)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
[![Website](https://img.shields.io/badge/website-myretromac.app-orange)](https://myretromac.app)

> Screenshots and demo videos live at **[myretromac.app](https://myretromac.app)**.

---

## What it does

RetroMac has two core ideas:

1. **Real-time CRT/retro shader over the whole screen** (or a single window). Using
   ScreenCaptureKit + Metal it draws a click-through overlay and renders it with shaders:
   CRT curvature, scanlines, NTSC dot-crawl, VHS, bloom, vignette and more. Dozens of
   presets (CRT GDV Mini Ultra, Joel GDV NTSC v4, LCD/PVM/Trinitron looks) with sliders
   for intensity, vignette and bloom.

2. **Retro desktop themes** via `.retromactheme` bundles: a floating dock, wallpaper, icon
   set and, per era, its own desktop (Program Manager, Toolchest, WindowShade and the rest).

## Features

- **Retro Dock** — floats over the system Dock; bottom/left/right; magnifier or hover-zoom;
  per-theme icons, trash and running-app indicators.
- **Themes** — Mac OS System 6 (true 1-bit black & white), Mac OS System 9 (Platinum),
  Mac OS X Aqua & Cheetah, Snow Leopard, Windows 3.1 / 98 / 98 Plus! / XP / 7 (Aero),
  BeOS, OS/2 Warp, SGI IRIX, AmigaOS Workbench, and more.
- **Themed cursors** — each theme can replace the system cursor (classic Mac watch/spinner,
  Aqua beach ball, Windows XP), captured and restored exactly when the theme goes off.
- **Virtual Camera** — a CMIO system extension applies the shader to your webcam feed for
  video calls, as a "RetroMac Cam" device.
- **Television** — web and stream content inside a retro-shaded window, with fullscreen.
- **Retro Games** — built-in Doom/Quake/Duke Nukem engines, Warcraft I + II natively on the
  bundled Stratagus engine with your own game data, plus an emulator installer + ROM library.
- **Retro Mode** — one click hides the Dock, menu bar and desktop icons, sets your favourite
  theme + shader, and restores everything on exit, quit or after a crash.
- **Timer** — run the shader or Retro Mode during a daily time window or for X minutes.
- **Screenshot with shader** via a global hotkey.
- **Widgets** — clock, CPU monitor, calculator, and era-specific toys (Nyanochrome cat,
  Tic-Tac-Toe) on the classic Mac desktops.

For the full history see the [Changelog](CHANGELOG.md).

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel (the release build is a universal binary)

## Install

Download the signed, notarized DMG from the
[Releases page](https://github.com/klotzbrocken/RetroMac/releases) or from
[myretromac.app](https://myretromac.app), then drag RetroMac into `/Applications`.

RetroMac is **free to use**. An optional [Pro unlock](https://klotzzy2.gumroad.com/l/retromac-licence)
supports development and lifts the limits on premium themes and effects. No tracking,
ad-free, entirely optional.

On first launch, grant **Screen Recording** (for the shader) and, if you want the virtual
camera, **Camera** access in System Settings ▸ Privacy & Security.

## Build from source

```sh
git clone --recurse-submodules https://github.com/klotzbrocken/RetroMac.git
cd RetroMac
./build.sh debug      # local dev build, signed with a standard Apple Development identity
open "/Applications/RetroMac Dev.app"
```

- Requires the Xcode command-line toolchain (Swift 6, macOS 14 SDK).
- `./build.sh debug` uses reduced entitlements (no system-extension install) so it launches
  without a provisioning profile; the virtual camera is release-only.
- `./build.sh release` and `./package.sh` produce the signed, notarized DMG and need the
  maintainer's Developer ID certificate — contributors normally use the debug build.
- The Warcraft engine lives in the `vendor/peonpad` submodule and is built on demand.

## Custom shaders

RetroMac can load your own Metal shader presets. See
[docs/CUSTOM-SHADERS.md](docs/CUSTOM-SHADERS.md).

## Updates

Automatic updates are delivered via [Sparkle](https://sparkle-project.org/) from the
[GitHub Releases](https://github.com/klotzbrocken/RetroMac/releases) feed.

## A note on sandboxing

RetroMac runs unsandboxed — this is required to control the Dock, menu bar and system UI.
It ships with the Hardened Runtime and is Developer-ID signed and notarized as mitigation.
See [SECURITY.md](SECURITY.md) for the security policy and how to report a vulnerability.

## License

RetroMac is released under the [GNU GPL v3.0](LICENSE). The paid Pro unlock is an optional
way to support the project; the source remains free software.

## Support & links

- Website: [myretromac.app](https://myretromac.app)
- Buy me a coffee: [ko-fi.com/N4N11K1NC](https://ko-fi.com/N4N11K1NC)
- Sister app (skinnable email client): [Reframe](https://myretromac.app/reframe)
- Maintainer: [klotzbrocken.de](https://www.klotzbrocken.de)
