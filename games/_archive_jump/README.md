# Archived Jump Game

This directory contains an early prototype Godot project for a side-scrolling jumping platformer. It's preserved as a learning artifact and **not actively developed**.

## Status

- **Frozen.** No new features.
- Bug fixes only if needed for archival hygiene.
- Code is referenced for ideas but **not copied** into other LevelCraft games.

## What's here

- A Godot 4.x project (open `project.godot`)
- 4 hand-designed levels of "world 1" (in `levels/`), plus stubs for further worlds
- A migrated v2 level format (single JSON per level: terrain grid + entity list, see CSV-to-JSON migration history in repo)
- A read-only level editor scaffold (`scenes/editor.tscn`) for browsing levels
- An HTML5 export at `dist/`
- Two visual style folders under `sprites/`:
  - `default/` — the original classic-platformer look
  - `sci/` — a sci-fi/grayscale robot look in the LevelCraft visual language

## Why archived

Rather than building a level editor for this game, the project pivots to **LevelCraft: Ricochet** (see `../ricochet/`), whose simpler 4-direction wall-bounce mechanic maps more cleanly onto a player-facing editor and lets us ship faster. See `../../docs/decisions.md` ADR-001.

This game may be revived in the future under its own non-IP-conflicting brand if/when there's reason. Until then: hands off, no new features.
