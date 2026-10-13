# Retro 3D Maze

A recreation of the classic Windows 3D Maze. You walk through a random maze of brick corridors, with a wooden floor and tiled ceiling.
- **Rats** scurry about.
- **Grey spinning shapes** turn the world upside down when you pass through them, and the next one turns it back.
- **The finish** is a spinning smiley. Reaching it fades to black and starts a new maze.

The walk keeps its right hand on the wall, the classic way out of a maze. So, like the original, it wanders into dead ends and turns around in them.

Built with SceneKit, from scratch: no Microsoft code or artwork. The original's "OpenGL" billboards are left out. Not affiliated with or endorsed by Microsoft. Windows is a trademark of Microsoft Corporation.

## Options

- **Maze size**: small (8×8), medium (12×12) or large (16×16).
- **Speed**, the number of **Rats** (up to 6) and **Flippers** (up to 10).
- **Show map**: an overlay map of the maze, your path so far, and the finish.

## Test app flags

For snapshots, use `make snapshot SAVER=Maze ARGS="…"`:

- `--maze small|medium|large`, `--rats 0…6`, `--flippers 0…10`, `--map`
- `--overview`: look down on the whole maze from above, to check where everything is.

## Code

- `MazeLayout.swift`: the maze (a randomised depth-first search), the start and finish, and the right-hand rule.
- `MazeScene.swift`: building each maze, the walk, the rats, the flips, and the fades between mazes. The walls, floor and ceiling are built once per maze, all the walls as a single mesh, so a frame only moves the camera, the rats and the spinning shapes. It uses about 5% of one CPU core at 60 fps (see `make perf`).
- `MazeModels.swift`: the rat, the flipper, the smiley, and the quad builder for walls, floor and ceiling.
- `MazeTextures.swift`: the brick, wood floor and ceiling tile textures and the smiley, generated in code.
- `MazeMap.swift`: the overlay map.
- `MazeSaverView.swift`, `MazeOptions.swift`, `MazeSettings.swift`: the view, the Options sheet, and the saved settings.
