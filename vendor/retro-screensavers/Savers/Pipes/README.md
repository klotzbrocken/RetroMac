# Retro Pipes

A recreation of the classic Windows 3D Pipes. Shiny pipes grow through a deep 3D grid with ball and elbow joints, seen in strong perspective from a slightly different angle each screen. Once the screen fills up, it dissolves to black in random blocks and starts over.

It runs at 30 fps, since only the growing pipe tips move, and merges each finished pipe into one mesh. That keeps it at about 4% of one CPU core (see `make perf`).

Built with SceneKit, from scratch: no Microsoft code or artwork. Not affiliated with or endorsed by Microsoft. Windows is a trademark of Microsoft Corporation.

## Options

- **Joints**: elbows, ball joints, or mixed (each pipe picks one).
- **Surface**: solid colors, or a texture wrapped around the pipes (marble, wood, granite, or mixed textures).
- **Pipes at once** and **Speed**.

About 1 in 300 ball joints is drawn as a Utah teapot, like in the original, so it never appears with elbows-only joints.

## Test app flags

Use these with `make run SAVER=Pipes ARGS="…"` or `make snapshot SAVER=Pipes ARGS="…"`:

- `--teapot-chance 0…1`: make teapots common enough to see.
- `--joints elbow|ball|mixed` and `--surface solid|marble|wood|granite|mixedTextures`: snapshots only; the window uses the saved Options.
- `--dissolve 0…1`: snapshots only; shows the wipe part-way through.

## Code

- `PipesScene.swift`: the simulation (grid walk, turns, joints, fill and reset cycle, camera). It runs on SceneKit's render thread.
- `PipeKit.swift`: materials and shared geometry per color or texture (the textures themselves are `RetroTexture`, in `Shared/Common`). It includes the quarter-torus elbow mesh and a shader modifier that keeps textures from stretching along straight runs.
- `Teapot.swift`: the Utah teapot, tessellated from Newell's original Bézier patches.
- `DissolveOverlay.swift`: the random-blocks wipe, drawn as a SpriteKit overlay.
- `PipesSaverView.swift`, `PipesOptions.swift`, `PipesSettings.swift`: the view, the Options sheet, and the saved settings.
