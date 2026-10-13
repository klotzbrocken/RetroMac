# Retro 3D Text

A recreation of the classic Windows 3D Text. Your own words, or the current time, extruded in 3D and turning in the middle of the screen.

Built with SceneKit, from scratch: no Microsoft code or artwork. Not affiliated with or endorsed by Microsoft. Windows is a trademark of Microsoft Corporation.

## Options

- **Display**: your text (up to 40 characters) or the current time, in your Mac's time format.
- **Font**: classic fonts that ship with macOS, from Arial Black and Impact to Comic Sans MS.
- **Rotation**: none, spin, see-saw, wobble or tumble, plus **Speed**.
- **Size**: how much of the screen width the text spans.
- **Surface**: chrome, a solid **Color**, or marble, wood or granite (the same textures as Retro Pipes).
- **Specular highlights** on or off.

## Test app flags

For snapshots, use `make snapshot SAVER=Text3D ARGS="…"`:

- `--text "Hello"` or `--clock`
- `--font <index>` and `--color <index>`, counting from 0 in the order the Options menus list them
- `--rotation none|spin|seeSaw|wobble|tumble`
- `--surface solid|chrome|marble|wood|granite`

## Code

- `Text3DScene.swift`: the text (SceneKit's `SCNText`, with a small bevel), the rotation styles, the surfaces, and the chrome environment. Chrome reflects a generated cube map: a deep blue sky, a white horizon, a dark floor, and two studio lights that glint as the text turns. Textures are projected straight onto the letters by a small shader, since `SCNText`'s own texture coordinates smear them.
- `Text3DSaverView.swift`, `Text3DOptions.swift`, `Text3DSettings.swift`: the view, the Options sheet, and the saved settings.

The text only changes when you change it (or once a second for the time), so a frame is mostly just a new rotation. It uses about 3% of one CPU core at 60 fps (see `make perf`).
