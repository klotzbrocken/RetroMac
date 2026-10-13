# Retro Starfield

A recreation of the classic Windows Starfield Simulation. You fly through a field of stars that stream out of the depths, dim and grey in the distance, then brightening and growing as they rush past the edges of the screen.

Built with SceneKit, from scratch: no Microsoft code or artwork. Not affiliated with or endorsed by Microsoft. Windows is a trademark of Microsoft Corporation.

## Options

The original's two settings:
- **Warp speed**
- **Star density:** 200 to 4,000 stars.

## Test app flags

For snapshots, use `make snapshot SAVER=Starfield ARGS="…"`:

- `--warp 0.2…4`
- `--stars 200…4000`

## Code

- `StarfieldScene.swift`: the stars and their flight. All the stars are a single point mesh drawn in one call, and the GPU moves them. Each star keeps a fixed spot and a phase along its flight, and a small shader places it from a shared clock. So per frame the CPU only advances that clock, however many stars there are. It uses about 5% of one CPU core at 60 fps (see `make perf`).
- `StarfieldSaverView.swift`, `StarfieldOptions.swift`, `StarfieldSettings.swift`: the view, the Options sheet, and the saved settings.
