# CLAUDE.md

This file provides project-specific instructions for Claude Code (and other AI coding assistants) working on this repository.

## Project Overview

This is a **2D platformer game** (Super Mario style) built with **Phaser 4**. The project includes:

- **Game runtime** — playable in browser, with planned distribution to PC/Mac (via Tauri) and mobile (via Capacitor).
- **Level editor** — a web-based editor for creating, editing, and saving levels. Levels are stored as JSON and shared between the editor and the game runtime.

The web is the primary platform. Native desktop and mobile builds wrap the same web codebase.

## Tech Stack

- **Phaser 4.1.0+** — game engine (WebGL renderer, Arcade Physics)
- **TypeScript** — all game and editor code
- **Vite** — dev server and bundler
- **Tiled** (optional) — external tilemap editor; levels can also be created via the in-game editor
- **Tauri** — desktop packaging (preferred over Electron for smaller bundle size)
- **Capacitor** — mobile packaging (iOS/Android)

## CRITICAL: Phaser Version

**This project uses Phaser 4, NOT Phaser 3.** This matters because:

- Phaser 4 was released April 10, 2026 (current version: 4.1.0 "Salusa").
- Most online tutorials, Stack Overflow answers, and AI training data describe Phaser 3.
- v3 and v4 share most of the public API, but there are important breaking changes.

**Before writing any Phaser code, consult these references in order:**

1. **`docs/phaser-skills/`** — Official Phaser 4 AI agent skill files (see "Official Skills" section below).
2. **`PHASER_V4_NOTES.md`** — Project-specific notes on v3 vs v4 differences and gotchas we've hit.
3. **`https://docs.phaser.io`** — Official API docs (these are v4).
4. If still unsure, use web_search to verify against current Phaser 4 documentation.

**Do NOT default to v3 patterns from training data.** When in doubt, read the skill file for the relevant subsystem first.

## Official Skills

The Phaser team ships an official set of AI agent skills with the Phaser 4 source code. We have copied these into `docs/phaser-skills/` for direct reference. The skills cover every major Phaser subsystem:

- `phaser-skills/v3-to-v4-migration/SKILL.md` — Every breaking change between v3 and v4 with exact replacements. **Read this first when uncertain about an API.**
- `phaser-skills/v4-new-features/SKILL.md` — New v4 features (Filters, SpriteGPULayer, TilemapGPULayer, etc.)
- `phaser-skills/game-setup-and-config/SKILL.md` — Game config, scene structure
- `phaser-skills/scenes/SKILL.md` — Scene lifecycle, transitions
- `phaser-skills/arcade-physics/SKILL.md` — Arcade Physics (the engine we use for the platformer)
- `phaser-skills/tilemaps/SKILL.md` — Tiled workflow, TilemapLayer, TilemapGPULayer
- `phaser-skills/input/SKILL.md` — Keyboard, mouse, touch, gamepad
- `phaser-skills/animations/SKILL.md` — Spritesheets, animation manager
- `phaser-skills/cameras/SKILL.md` — Camera follow, bounds, zoom, shake
- `phaser-skills/tweens/SKILL.md`
- `phaser-skills/particles/SKILL.md`
- `phaser-skills/filters-and-postfx/SKILL.md` — v4's unified Filter system (replaces v3 FX/Masks)
- ...and ~16 more skills covering audio, UI, text, shaders, lighting, etc.

**Workflow for adding a feature:**

1. Identify which subsystem(s) the feature touches.
2. Read the corresponding SKILL.md file(s).
3. Then write the code.

The official Phaser 4 source is at https://github.com/phaserjs/phaser. To update our local copy of skills, copy the latest `skills/` directory from that repo into `docs/phaser-skills/`.

## Architecture Conventions

### Code organization

```
src/
  game/           # Phaser game runtime (Scenes, GameObjects, etc.)
    scenes/
    entities/     # Player, enemies, etc.
    physics/      # Custom physics helpers if needed
  editor/         # Web-based level editor (separate entry point)
  shared/         # Code used by both game and editor
    level-format/ # Level JSON schema + serialization
    tile-defs/    # Tile definitions
  main.ts         # Game entry point
  editor.ts       # Editor entry point
```

### Level data format

- Levels are plain JSON, schema defined in `src/shared/level-format/`.
- Both the editor and game runtime read/write this same format.
- The format must remain forward-compatible — when adding fields, default them sensibly so old levels still load.

### Tilemap rendering

- **In the editor:** use the standard `TilemapLayer` (CPU-side; supports tile editing).
- **In the game runtime:** prefer `TilemapGPULayer` for static level geometry (much faster). Use standard `TilemapLayer` only for layers that change at runtime (e.g., destructible terrain).

### Physics

- Arcade Physics only. Do not add Matter.js — it's overkill for a tile-based platformer and the feel is harder to dial in.
- Custom platformer feel features (coyote time, jump buffer, variable jump height, corner correction) live in `src/game/entities/Player.ts`. These are NOT generic physics features — they are specific to platformer feel.

### Game feel constants

Things like jump height, run speed, coyote time window, etc. live in a single `src/game/config/feel.ts` file so they can be tuned in one place. Do not scatter magic numbers across the codebase.

## Coding Style

- TypeScript strict mode is on.
- Prefer composition over inheritance for game entities.
- All Phaser GameObjects that represent game entities (Player, Enemy, etc.) should be wrapped in TypeScript classes with explicit typed interfaces, not used directly as raw Sprites.
- Asset keys are constants, defined in `src/game/config/assets.ts`. Do not hardcode strings like `'player'` across files.

## Common Tasks

### Running the game (dev)
```bash
npm run dev
```

### Running the editor (dev)
```bash
npm run dev:editor
```

### Building for web
```bash
npm run build
```

### Building for desktop (Tauri)
```bash
npm run tauri:build
```

### Building for mobile (Capacitor)
```bash
npx cap sync && npx cap open ios   # or android
```

## Things to NOT Do

- ❌ Do not use Phaser 3 API patterns (see `PHASER_V4_NOTES.md` for the common ones).
- ❌ Do not use deprecated `setTintFill()` — use `setTintMode()` in v4.
- ❌ Do not import the removed `Phaser.Geom.Point` — use `Phaser.Math.Vector2`.
- ❌ Do not add Matter.js for platformer physics. Arcade Physics + custom feel logic is the right fit.
- ❌ Do not put localStorage/sessionStorage calls in shared code — they don't work in all packaging targets uniformly. Use a storage abstraction in `src/shared/storage/`.
- ❌ Do not use the Canvas renderer. v4's WebGL renderer is the path forward; Canvas is deprecated and lacks v4's features.
- ❌ Do not make direct WebGL `gl.*` calls. If WebGL access is needed, use an Extern game object so Phaser's state wrapper stays in sync.

## When You're Unsure

If you're about to write Phaser code and you're not sure if an API is v3 or v4:

1. Check `docs/phaser-skills/` for the relevant subsystem.
2. Check `PHASER_V4_NOTES.md` for known gotchas.
3. If still unsure, web_search the current Phaser docs (docs.phaser.io is v4).
4. If a v3 pattern looks like it might still work but you're not 100%, ask the human before committing.

It's much cheaper to spend 30 seconds reading a skill file than to debug a v3-vs-v4 API mismatch later.
