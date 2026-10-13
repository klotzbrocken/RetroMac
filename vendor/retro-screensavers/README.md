# retro-screensavers

A collection of macOS screen savers recreating classics from the 90s. Each one is its own `.saver` bundle, so it shows up separately in System Settings with its own thumbnail and options.

| Screen saver | |
| --- | --- |
| [Retro Pipes](Savers/Pipes/README.md) | The Windows 3D Pipes: pipes grow through a deep 3D grid with ball and elbow joints, solid or textured, and the screen dissolves to black in random blocks when it fills up. Teapot included. |
| [Retro Flower Box](Savers/FlowerBox/README.md) | The Windows 3D Flower Box: a colorful shape floats and tumbles across the screen while it swells into balloon petals, shoots out spikes, rounds into a volleyball and snaps back. Cube, tetrahedron, pyramid, cylinder or spring. |
| [Retro 3D Text](Savers/Text3D/README.md) | The Windows 3D Text: your own words or the current time, extruded in 3D and spinning, rocking, wobbling or tumbling. Chrome, solid color, marble, wood or granite. |
| [Retro Starfield](Savers/Starfield/README.md) | The Windows Starfield Simulation: flying through a field of stars that stream out of the depths, brightening and growing as they pass. Warp speed and star density. |
| [Retro 3D Maze](Savers/Maze/README.md) | The Windows 3D Maze: walk through a random brick maze with rats scurrying about and grey spinners that turn the world upside down, until you reach the smiley and a new maze begins. Optional map. |

## Install

Requires macOS 14 Sonoma or later, on Apple Silicon or Intel.

Paste this into Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/AdrianJHerskind/retro-screensavers/main/install.sh | bash
```

It downloads the [latest release](https://github.com/AdrianJHerskind/retro-screensavers/releases/latest), installs every saver into your `~/Library/Screen Savers`, and opens System Settings → Screen Saver, where they're listed under **Other**, at the bottom. **Options…** opens a saver's settings. It doesn't need your password, and macOS doesn't block the savers this way even though they aren't notarized. Feel free to [read the script](install.sh) first. To install only some savers, or to uninstall them all:

```bash
curl -fsSL https://raw.githubusercontent.com/AdrianJHerskind/retro-screensavers/main/install.sh | bash -s -- Pipes Text3D
```

```bash
curl -fsSL https://raw.githubusercontent.com/AdrianJHerskind/retro-screensavers/main/install.sh | bash -s -- --uninstall
```

### Installing by hand

1. Download `RetroScreensavers.zip` from the [latest release](https://github.com/AdrianJHerskind/retro-screensavers/releases/latest) and unzip it. Safari usually unzips it for you.
2. The savers aren't notarized by Apple, so macOS blocks them when they're downloaded. To allow them, run this once in Terminal (adjust the path if the folder isn't in Downloads):
   ```bash
   xattr -dr com.apple.quarantine ~/Downloads/"Retro Screensavers"
   ```
3. Double-click each saver you want in the "Retro Screensavers" folder, and choose to install it.

## Building from source

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

| Command | What it does |
| --- | --- |
| `make install` | Builds every saver (Release) and copies them to `~/Library/Screen Savers`. Then pick one in System Settings → Screen Saver. Local builds aren't blocked, so there's no `xattr` step. |
| `make uninstall` | Removes them again. |
| `make dist` | Builds every saver into one `dist/RetroScreensavers.zip`, ready to attach to a GitHub release. `install.sh` downloads it from the latest release. |
| `make run SAVER=Pipes` | Opens a saver's test app, which shows it in a normal window (⌘, for options, ⌃⌘F for full screen). It's an optimized build, so it performs like the real saver; to use the debugger, run the `<Name>Harness` scheme from Xcode. Saver-specific flags go in `ARGS`. |
| `make snapshot SAVER=Pipes ARGS="--time 30"` | Renders one frame offscreen to `build/snapshot.png`; also takes `--size WxH` and `--seed n`. |
| `make thumbnails SAVER=Pipes` | Regenerates the saver's System Settings tile in `Savers/<Name>/Resources`. |
| `make perf` | Measures each saver's CPU and memory use (and system-wide GPU use) in its test app, and warns if one is over budget; `SAVER=<Name>` for just one. See [Performance](#performance). |
| `make project` | Generates `RetroScreensavers.xcodeproj` from `project.yml`, for working in Xcode. |

`SAVER` defaults to `Pipes`.

## Layout

- `Savers/<Name>/`: one screen saver, built as `Retro<Name>.saver`.
  - `Sources/`: its code, compiled as its own Swift module, so savers can't clash with each other.
  - `Harness/`: hooks it into the shared test app (a `HarnessSaver` type conforming to `HarnessSupport`).
  - `Resources/`: thumbnails and anything else bundled with it.
  - `Info.plist`: names the principal class and the display name.
- `Shared/Common/`: compiled into every saver.
  - `RetroScreenSaverView`: the base class; handles the host quirks below.
  - `OptionsSheet`: the standard Options sheet layout.
  - Small helpers such as a seedable random number generator.
- `Shared/Harness/`: the test app and the offscreen snapshot and thumbnail renderer, compiled into each saver's harness. It also has `PerformanceProbe`, the measuring side of `make perf`.
- `Tools/perf-check.sh`: the performance budget check behind `make perf`.

## Performance

These should run as lightly as the originals did on 90s hardware. Every saver declares the frame rate it needs (Pipes 30 fps, since only its pipe tips move; Flower Box 60 fps, since the whole object keeps moving). On battery or in Low Power Mode, all of them drop to at most 30 fps, and go back up when the Mac is plugged in again.

`make perf` runs each saver's test app, skips a warm-up, and measures its CPU time and memory for 30 seconds. It then prints a table and exits with an error if a saver averages more than 20% of one CPU core. On an M3 Pro, plugged in:

```
Saver          CPU avg  CPU peak      Memory        GPU
FlowerBox        12.2%     16.6%      291 MB        20%   ok
Maze              5.0%      5.4%      182 MB        35%   ok
Pipes             3.8%      5.0%      228 MB        19%   ok
Starfield         4.7%      9.1%      251 MB        14%   ok
Text3D            3.1%      4.5%      184 MB        23%   ok
```

`HARNESS_ARGS=--battery make perf` measures the battery frame rates (Flower Box drops to about 5%). Budgets and durations are set with environment variables too, e.g. `CPU_LIMIT=15 MEASURE_SECONDS=60 make perf`. `GPU_LIMIT` adds a GPU budget, but macOS only reports GPU use for the whole system, so close other busy apps first. The test app windows have to stay visible while they're measured. Run it before releasing, or after any change that touches drawing.

## Adding a screen saver

1. Create `Savers/<Name>/` with `Sources/`, `Harness/` and an `Info.plist` (copy the one from Pipes and change `NSPrincipalClass` and the names).
2. In `Sources/`, subclass `RetroScreenSaverView` and give it a unique Objective-C name matching the plist, e.g. `@objc(RetroStarfieldSaverView)`. Override `setAnimating(_:)` to start and stop drawing, and `frameRateDidChange()` to apply `frameRate`. Set `fullFrameRate` if the saver doesn't need 60 fps.
3. In `Harness/`, add an `enum HarnessSaver: HarnessSupport`.
4. Add the targets to `project.yml`:
   ```yaml
   <Name>:
     templates: [ScreenSaver]
   <Name>Harness:
     templates: [Harness]
     templateAttributes:
       saver: <Name>
   ```
5. Run `make run SAVER=<Name>` to try it, then `make thumbnails SAVER=<Name>`, `make perf SAVER=<Name>` and `make install`.

## macOS quirks handled

- Since Sonoma, third-party savers run inside `legacyScreenSaver`. It doesn't reliably call `stopAnimation()` and keeps old instances alive. `RetroScreenSaverView` listens for `com.apple.screensaver.willstop`, stops drawing, and quits the host process (never for the System Settings preview or the test app).
- `legacyScreenSaver` caches loaded bundles, so `make install` quits it to pick up new builds.
- System Settings can load several savers into one process, so each principal class has its own explicit Objective-C name.

## Sharing it

Local builds are ad-hoc signed, which is enough on this Mac. To give the `.saver` files to other people, sign them with a Developer ID and notarize them; otherwise Gatekeeper blocks them. If you publish your own fork, change `BUNDLE_ID_PREFIX` in `project.yml` to a prefix you own.

## License

MIT; see [LICENSE](LICENSE).

These are independent recreations, written from scratch. Not affiliated with or endorsed by Microsoft. Windows is a trademark of Microsoft Corporation.
