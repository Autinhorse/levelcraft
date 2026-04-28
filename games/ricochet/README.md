# LevelCraft: Ricochet

The first publicly-shipped game on the LevelCraft platform. A 2D tile-based platformer where the player launches the hero in cardinal directions; the hero flies until hitting something. See `design/design.md` for the full spec.

## Phase 1 — mechanic feel-test (current)

Hardcoded one-room test level, placeholder colored rectangles for visuals, no editor, no real assets, no menu chrome. Goal: validate the launch-and-stop movement and Space jump feel correct.

### How to run
1. Open Godot 4.6 (Compatibility renderer is fine — that's what `project.godot` selects).
2. **Project → Import…** → point at `games/ricochet/project.godot`.
3. Open the project, then F5 (Run main scene).
4. The scene auto-builds a test room with walls, one hazard tile, and the player at spawn.

### Controls
| Key | On the floor | Mid-jump (Space arc) |
| --- | --- | --- |
| ← / → | Rise 1 tile, then launch horizontally at 5 t/s | Cancel arc, launch left/right at 5 t/s from current air position |
| ↑ | Launch straight up at 5 t/s | Same as on-floor |
| ↓ | (no-op in v1, reserved) | Cancel arc, launch straight down at 5 t/s |
| Space | Vertical jump, 2-tile peak; arrow keys remain active during full arc | — |

After a horizontal launch hits a wall: rebound 1 tile, brief pause, fall under gravity. After a vertical-up launch hits a ceiling: brief pause, fall.

### Project layout
```
games/ricochet/
├── project.godot
├── icon.svg
├── design/design.md       Game design doc (canonical for mechanic + editor)
├── scenes/play/play.tscn  Main scene (Node2D + scripts/play.gd)
├── scripts/
│   ├── play.gd            Builds the hardcoded test room, instantiates Player
│   └── player.gd          Player CharacterBody2D + state machine
├── assets/sprites/        (empty until real assets land)
└── levels/                (empty until JSON level loader lands)
```

## What Phase 1 doesn't include yet
- Level editor — Phase 2.
- JSON level loading — Phase 3 (currently the test room is a hardcoded array in `play.gd`).
- Real art assets — generated later in the LevelCraft style; placeholder colored rects for now.
- Menu, level list, HUD, sound — all later.
- Multi-page levels, teleporters, level-end goal — later.
