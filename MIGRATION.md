# Migration Plan: Single Project → LevelCraft Platform

This document describes how to evolve the **current Godot project** (which contains a Mario-style platformer with World 1's 4 levels and ~half of SMB1's tile/entity variety, but no level editor) into the **LevelCraft platform structure** described in `CLAUDE.md`.

## Starting State

A single Godot project containing:
- Play mode (gameplay engine for a Mario-style jumping platformer)
- 4 implemented levels (World 1)
- About half the visual variety of Super Mario Bros 1 (tiles, entities, mechanics)
- A grayscale sci-fi robot visual style (assets generated via ChatGPT)
- **No level editor / maker yet** — this would be substantial additional work

## Target State

A monorepo structure that:
- **Archives** the existing jump game in `games/_archive_jump/` (frozen, not actively developed)
- **Adds Ricochet** as a fresh new Godot project (`games/ricochet/`) — the priority game
- Has a separate `web/` folder for the platform website + backend (later phase)
- Keeps a clear separation between "platform" code and "game" code
- Establishes the LevelCraft visual style as a documented standard, applied to both games (with separate asset files per game, see `CLAUDE.md`)

## Why This Migration Matters

The current project structure is single-game. We need to refactor before:
1. Starting Ricochet — to avoid copying boilerplate or entangling code
2. Starting the web platform — to avoid coupling game code with platform code
3. Defining the level data format — so it's portable across games

**Doing this refactor now is cheap. Later, after web code is intertwined, it's expensive.**

---

## Migration Steps

### Step 1: Archive the Existing Jump Game

The existing Godot project contains a Mario-style platformer that:
- Cannot ship under any Mario-related branding (Nintendo IP risk)
- Lacks a level editor (would be substantial work to build)
- Is **superseded by Ricochet** as the priority

**Action:**

1. Create the new monorepo directory layout (Step 2 below) first, to give us the target paths.
2. Move the existing Godot project into `games/_archive_jump/`. Preserve full git history — use `git mv` for all files so history follows.
3. **Strip any Mario-related naming, comments, or assets** from the moved code:
   - Search for `mario`, `Mario`, `MARIO` in code, comments, scene names, asset names, project files
   - Rename anything you find
   - Document what you removed in `docs/lessons.md` under an entry like:
     ```
     ## YYYY-MM-DD: Archived jump game — IP cleanup
     - Removed Mario references from: [list of files]
     - Lesson for GameByTalk: any project that "looks like" a known IP needs upfront naming hygiene; retroactive cleanup is annoying.
     ```
4. Add a `games/_archive_jump/README.md` explaining:
   - This is an archived early prototype of a jumping platformer
   - It is NOT actively developed
   - It uses the LevelCraft visual style (see `CLAUDE.md`)
   - It may be revived in the future under a proper non-Mario brand
5. **Do NOT delete the project** — it has working game code that's a useful reference and may be revived.

### Step 2: Set Up the Monorepo Structure

Create this directory tree at the repo root:

```
levelcraft/
├── CLAUDE.md                    (already exists — strategic context)
├── MIGRATION.md                 (this file)
├── PROJECT-OVERVIEW.md          (high-level project summary)
├── README.md                    (the existing repo README)
├── .gitignore
├── games/
│   ├── _archive_jump/           (the old project, moved here in Step 1)
│   │   └── README.md            (explains the archive)
│   └── ricochet/                (new, empty for now — see Step 3)
├── web/
│   ├── frontend/                (new, empty for now — Step 5)
│   └── backend/                 (new, empty for now — Step 5)
├── shared/
│   └── level-schema/            (new, empty for now — Step 4)
└── docs/
    ├── lessons.md               (start it now, even if mostly empty)
    └── decisions.md             (start it now, record the archive decision)
```

**For each new directory, add a `README.md`** describing what goes there. This is for future-you and Claude Code to keep bearings.

**Initial entry in `docs/decisions.md`:**

```markdown
# Architecture Decision Records

## ADR-001: Archive the existing jump game, ship Ricochet first

**Date:** YYYY-MM-DD
**Status:** Accepted

**Context:** The repo has an existing Mario-style platformer with 4 levels but no level editor. Building the editor would be substantial work. Meanwhile, Ricochet (a wall-bouncing platformer) has simpler mechanics that map more cleanly to a level editor.

**Decision:** Archive the existing jump game in `games/_archive_jump/` (frozen, not actively developed). Build Ricochet from scratch as the first publicly shipped LevelCraft game.

**Consequences:**
- Existing jump game work is not lost but not progressed
- Ricochet can be shipped faster (simpler mechanics)
- "Doubter response" public traction story is cleaner with one focused game
- The archived game can be revived later under a proper non-Mario brand if desired
```

### Step 3: Initialize the Ricochet Godot Project

In `games/ricochet/`:

1. **Create a new Godot 4.x project** — do NOT copy from `_archive_jump`. Start fresh.
2. **Target HTML5 export** as the primary platform (so it runs in browser).
3. **Set up project structure:**
   ```
   games/ricochet/
   ├── project.godot
   ├── scenes/
   │   ├── play/                 (gameplay scene)
   │   ├── editor/               (level editor scene — later)
   │   └── menu/
   ├── scripts/
   ├── assets/
   │   ├── sprites/              (Ricochet-specific assets, generated fresh)
   │   ├── audio/
   │   └── fonts/
   └── levels/                   (built-in starter levels in JSON)
   ```

4. **Generate Ricochet-specific assets in the LevelCraft visual style.**
   - Use the style guidelines from `CLAUDE.md` (grayscale palette, 64×64, sci-fi robot aesthetic, dark-to-light shading)
   - But design new sprites distinct from the archived jump game's robot
   - Suggestion: Ricochet's robot could be more compact / round (since it bounces around constantly), versus the jump game's more upright posture
   - Founder will likely use ChatGPT to generate these

5. **Implement the core launch-and-stop mechanic first.** See `games/ricochet/design/design.md` for the canonical spec. Summary:
   - Player visual is a small robot character with personality (NOT a generic square sprite); collision box is 1×1 cell.
   - Tile size 48×48 px. Game viewport: 25×20 cells (1200×960 px). Game window: 1600×960 (viewport centered, 400 px reserved for HUD/letterbox).
   - **Floor state (input accepted):** arrow keys launch in that direction at constant speed (5 cells/s). Left/right first lift one cell, then fly horizontally. Up flies straight up. Once launched, input is locked.
   - **In-flight:** keep moving until hitting something. On wall: rebound 1 cell, pause briefly, fall under gravity (10 cells/s², capped at 5 cells/s) until landing.
   - **Jump (Space, 2 cells from floor):** input is accepted during both ascent and descent — pressing an arrow key launches in that direction from the player's current mid-air position. Down arrow during a jump triggers a downward launch (mirror of up).
   - Out-of-bounds is treated as wall (no death pits in v1).
   - Hazards kill → respawn at level start.

6. **Implement basic level elements** (start minimal, expand later):
   - Solid walls / floors
   - Spikes (deadly)
   - Goal / exit
   - (Later: buttons, doors, moving platforms, etc. — but start simple)

7. **Build 3–5 hand-designed test levels** to validate the mechanic feels good.

**Do NOT yet:**
- Build the level editor for Ricochet — focus on `play` first
- Worry about user accounts, level sharing, or web integration — that's later
- Add menus or UI polish — minimum viable

### Step 4: Define the Shared Level Schema

In `shared/level-schema/`:

1. Define a JSON schema for a Ricochet level. Example:
   ```json
   {
     "id": "aB3xK9",
     "game_type": "ricochet",
     "schema_version": 1,
     "title": "First Level",
     "spawn": { "x": 2, "y": 10 },
     "goal": { "x": 28, "y": 10 },
     "tiles": [
       { "type": "wall", "x": 0, "y": 0, "w": 30, "h": 1 },
       { "type": "spike", "x": 5, "y": 1 }
     ]
   }
   ```
2. Document the schema in `shared/level-schema/ricochet.md`
3. The schema should be **versioned** (`schema_version` field) so we can evolve it without breaking old levels.
4. Future games will have their own schemas in this folder. The platform's `levels.data` JSONB field accepts any of them, validated by `game_type`.

**Why this matters:** When the web platform serves a level to the Godot game, it sends this JSON. The Godot game parses it and builds the level. This decoupling means:
- The web platform doesn't need to know Godot internals
- The level format can evolve independently from the game engine
- Future tools (level visualizers, AI generators for GameByTalk) can read this format

### Step 5: Set Up the Web Platform Skeleton

This is **not a priority for week 1**. After Ricochet's gameplay is solid, set up:

1. **Frontend** (`web/frontend/`): Next.js + TypeScript + Tailwind. Bare minimum:
   - Landing page (`/`)
   - Ricochet hub (`/ricochet`) listing levels
   - Embedded Godot HTML5 player at `/ricochet/play/[level_id]`
   - User auth pages (login, register)
   - User profile (`/u/[username]`)

2. **Backend** (`web/backend/`): Whatever stack you prefer — Node + tRPC, or Bun + Hono, or Go + chi. Provides:
   - Auth API (or delegated to Supabase)
   - Levels CRUD API
   - Upload-level endpoint (validates against schema)

3. **Database** (Postgres):
   - Schema as defined in `CLAUDE.md`
   - Migrations managed via Drizzle, Prisma, or sqlx — NOT raw SQL files

### Step 6: Connect Game ↔ Web

The Godot HTML5 export needs to talk to the web platform:
1. The Godot game receives a level ID via URL parameter
2. On load, it fetches the level JSON from the backend (`GET /api/levels/{id}`)
3. On level completion, it can POST a play record back (for analytics)

Use Godot's `HTTPRequest` node for this. Document the API contract in `docs/api.md`.

---

## What to Do First (Recommended Order)

If you have one week:

| Day | Task |
|-----|------|
| 1 | Steps 1, 2 — restructure the repo, archive jump game |
| 2–4 | Step 3 — get the Ricochet wall-bouncing mechanic feeling right (most important) |
| 5 | Step 4 — define and validate the level schema |
| 6 | Build 5–10 hand-designed Ricochet levels to validate the mechanic |
| 7 | Record a video of the game in action (for public traction post) |

Steps 5 and 6 (web platform, game-web integration) come **after** the gameplay is fun. **No point building the platform if the game isn't fun.**

---

## Anti-Patterns to Avoid

- **Don't copy code or assets from `_archive_jump` into `ricochet`.** Different game, different mechanics, fresh start. Lifting code wholesale will drag in assumptions that don't apply.
- **Don't try to make the Godot project "engine-agnostic" or support multiple games in one project.** Each game gets its own Godot project. Only the level schema is shared.
- **Don't build a "game framework" abstraction prematurely.** Build Ricochet concretely first; if and when a second game is built, refactor common patterns out then.
- **Don't try to do web platform setup before gameplay works.** Gameplay quality is the bottleneck; everything else is replaceable.
- **Don't try to revive the archived jump game during this migration.** It's archived for a reason — focus.

---

## Open Questions to Resolve with the Founder

Things this migration plan does NOT decide. Ask before assuming:

1. **Web stack final choice:** Next.js? SvelteKit? Just plain HTML + a tiny backend?
2. **Auth provider:** Roll our own (email + JWT)? Supabase Auth? Clerk?
3. **Database hosting:** Self-hosted Postgres? Supabase? Neon?
4. **CI/CD:** GitHub Actions? Just deploy from local for now?
5. **Asset workflow for Ricochet art:** Founder generates via ChatGPT, but what's the iteration loop? Where do they live before being committed? Naming convention?

Capture answers in `docs/decisions.md` once decided.
