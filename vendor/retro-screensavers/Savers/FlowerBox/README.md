# Retro Flower Box

A recreation of the classic Windows 3D Flower Box. A colorful shape floats across a black screen, bouncing off the edges and tumbling as it goes, while it morphs:
1. It swells its faces into balloon-like petals.
2. It shoots spikes out of its corners.
3. It draws the petals back in.
4. It rounds into a volleyball.
5. It snaps back to its plain shape.

Built with SceneKit, from scratch: no Microsoft code or artwork. Not affiliated with or endorsed by Microsoft. Windows is a trademark of Microsoft Corporation.

## Options

- **Shape**: cube, tetrahedron, pyramid, cylinder or spring. The spring has no faces or corners to bloom from, so it swells into a string of beads instead, and doesn't turn into a ball.
- **Size** and **Speed**.
- **Spin**, **Bloom** and **Cycle colors**, which can each be turned off.

## Test app flags

For snapshots, use `make snapshot SAVER=FlowerBox ARGS="…"`:

- `--shape cube|tetrahedron|pyramid|cylinder|spring`
- `--object-size 0.2…0.8`: the object's size as a share of the screen height.
- `--time`: seconds into the animation. One morph cycle takes 11.5 s at normal speed; full bloom is around 5.5 s and the ball around 9.5 s.

## Code

- `ShapeMesh.swift`: the shapes as curved patches, and the morph. While blooming, every point moves along its ray from the center, onto a shrunken core blended with one ball-shaped petal per face and one spike per corner. Because this depends only on direction, the patches stay joined whatever the shape.
- `FlowerBoxScene.swift`: the morph timeline, the floating, spinning and color cycling.
- `FlowerBoxSaverView.swift`, `FlowerBoxOptions.swift`, `FlowerBoxSettings.swift`: the view, the Options sheet, and the saved settings.

### Performance

Every morph cycle is identical; only the position, rotation and colors vary, and those don't touch the mesh. So `ShapeMesh` builds each frame's geometry once (30 per second of morph, with pauses sharing one) and keeps it. After the first cycle, drawing a frame just picks a geometry that's already on the GPU. Measured in the optimized test app, it uses about 12% of one CPU core at 60 fps, most of which is SceneKit's own per-frame overhead. On battery or in Low Power Mode it drops to 30 fps and about 5% (see `make perf`).
