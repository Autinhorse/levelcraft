# LevelCraft —— Project Context for Claude Code

> This file is the canonical project context. Claude Code should read this **before any other file** to understand what we're building, why, and what constraints apply.

**LevelCraft** is a platform for player-created game levels. It hosts multiple game types as sub-products. The first publicly shipped game will be **LevelCraft: Ricochet** (a wall-bouncing pixel platformer).


## The Things in This Repo's Mental Model

### 1. LevelCraft (this repo — the rehearsal product)
- A community platform where players hand-design levels using a visual editor
- Hosts multiple game types as sub-products
- Lower risk than GameByTalk, used to validate user systems / content systems / community mechanics
- **The point is not just the product itself — it's the experience and lessons that will inform GameByTalk.**

### 2. LevelCraft: Ricochet (this repo's first publicly shipped game — top priority)
- A 2D tile-based platformer with a deliberate, launch-and-stop movement mechanic
- The player is a small robot character with a 1×1 collision box, on a grid of solid tiles
- **Floor state (input accepted):** arrow keys launch the player at a constant speed in that direction. Left/right first lift the player one cell, then fly horizontally. Up flies straight up. Once launched, keyboard input is locked.
- **In-flight:** the player keeps moving until they hit something. On a wall: rebound by 1 cell, pause briefly, then fall under gravity until they land back on a floor (input accepted again).
- **Jump (Space):** vertical jump of 2 cells from the floor. During **both ascent and descent of the jump**, keyboard input is accepted — pressing any arrow key launches in that direction from the current mid-air position. So a jump lets the player choose where to launch from above floor level.
- Hazards kill the player; special tiles (sticky, teleporter, etc.) trigger their own behaviors.
- See `games/ricochet/design/design.md` for the full game design.
- Built with **Phaser 4 + TypeScript + Vite** in `games/ricochet/`. See "Ricochet Engine" below for layout and Phaser-specific docs.
- **This is the first concrete game shipped on the LevelCraft platform**

---

## Naming and Branding

### Always use:
- **Platform name:** `LevelCraft`
- **First game (active development):** `LevelCraft: Ricochet` (or just `Ricochet`)

**When in doubt, err toward making things look and feel original.**

---

## Visual Style — Shared Across LevelCraft Games

The founder has established a unified visual style for the LevelCraft platform:

**The "LevelCraft Style":**
- **Grayscale palette:** `#000000`, `#333333`, `#666666`, `#999999`, `#CCCCCC`, `#FFFFFF`
- **Sci-fi/tech aesthetic:** small robot characters, energy collectibles, futuristic backgrounds
- **Resolution:** 64×64 base tile/character grid; 32×32 for collectibles
- **Hand-illustrated, detailed** (not minimalist 1-bit pixel art) with dark-to-light gradient shading

**Rules for visual asset development:**

- ✅ All current and future LevelCraft games share this **visual language**
- ✅ But **asset files themselves are NOT shared** between games — each game gets its own assets, generated separately
- ✅ The founder uses ChatGPT (or similar) to generate concrete assets per game
- ✅ When prompting for new assets, reference: *"the LevelCraft style — grayscale palette (#000–#FFF), sci-fi robot/tech aesthetic, hand-illustrated 64×64 sprites with dark-to-light gradient shading"*

**Why share style but not assets:**
- Same style → unified LevelCraft platform brand (players recognize the family)
- Different assets → each game has its own visual identity within the brand
- AI-generating fresh assets per game is cheap, so duplication isn't a cost concern

---

## Architecture Overview

### URL Structure
```
levelcraft.gg/                          Platform homepage
levelcraft.gg/ricochet                  Ricochet hub (browse, featured levels)
levelcraft.gg/ricochet/play/{level_id}  Play a specific level
levelcraft.gg/ricochet/create           Level editor (when built)
levelcraft.gg/u/{username}              User profile (cross-game)
```

**Decisions:**
- Subdirectory (`/ricochet`), NOT subdomain. Better for SEO and brand cohesion.
- Game name in URL — URLs are self-documenting.
- User profile at platform level — designed for future cross-game content.
- Level IDs: short alphanumeric (6–8 chars), like `aB3xK9`. NOT sequential integers, NOT UUIDs.

### Repository Structure

```
levelcraft/                          (monorepo root)
├── CLAUDE.md                        (this file — strategic context)
├── README.md                        (repo README)
├── games/
│   └── ricochet/                    (Phaser 4 + TS + Vite project — see "Ricochet Engine" below)
├── web/
│   ├── frontend/                    (planned, not started)
│   └── backend/                     (planned, not started)
└── docs/
    ├── lessons.md                   (lessons learned, fed into GameByTalk)
    ├── decisions.md                 (architecture decision records)
    └── phaser-skills/               (on-demand Phaser API references — read when needed, not auto-loaded)
```

### Database Schema (Core Tables)

**Critical decision:** levels for all games live in **one table** with a `game_type` column. Do NOT create separate tables per game.

```sql
users (
  id              uuid primary key,
  username        text unique not null,
  email           text unique not null,
  email_verified  boolean default false,
  created_at      timestamptz
  -- Future fields (don't add now, but design schema to allow easy addition):
  -- payment_customer_id, subscription_tier (for GameByTalk later)
)

levels (
  id              text primary key,    -- short alphanumeric ID
  slug            text,                 -- optional human-readable slug
  game_type       text not null,        -- 'ricochet', future games...
  creator_id      uuid references users,
  title           text,
  description     text,
  data            jsonb,                -- game-specific level data
  status          text,                 -- draft, published, removed
  created_at      timestamptz,
  updated_at      timestamptz
)

-- Standard tables: likes, comments, plays_log, reports, follows
```

### Tech Stack
- **Game engine:** Phaser 4 (4.1.0+ "Salusa") — WebGL renderer, Arcade Physics
- **Game language / build:** TypeScript + Vite (dev server + bundler)
- **Game distribution:** browser-native; future native desktop via Tauri, mobile via Capacitor (same web codebase wrapped)
- **Web frontend:** TBD — recommend Next.js + TypeScript
- **Backend:** TBD — Node, Bun, or Go
- **Database:** Postgres (Supabase recommended for hosted Postgres + auth)
- **Auth:** Email + at least one OAuth (Google or Discord recommended)
- **Hosting:** Vercel (frontend), Fly.io / Railway (backend), Cloudflare R2 (assets)

---

## Ricochet Engine — Phaser 4 + TypeScript + Vite

The game lives in `games/ricochet/`. Source layout:
- `src/main.ts` — Phaser game config, scene registration, URL-mode boot (`?mode=edit` selects EditScene)
- `src/game/scenes/` — `PlayScene` (runtime), `EditScene` (level editor)
- `src/game/entities/` — `Player`, `Bullet`, `Cannon`, `Turret`, `Gear`, etc.
- `src/game/config/feel.ts` — tunable constants (colors, speeds, gravity, etc.)
- `src/shared/level-format/` — level JSON schema + loader, shared between play and edit
- `public/` — static assets, default level JSON

### Phaser version matters
This project is on **Phaser 4**, not Phaser 3. Most online tutorials, Stack Overflow answers, and AI-training data describe v3. v3 and v4 share most of the public API but have breaking changes — assume things may have moved and verify before copying patterns from the web.

### Phaser docs in this repo (read on demand — NOT auto-loaded)

These files are **not** `@`-imported by this CLAUDE.md, to keep the per-conversation token cost low. Read them with the Read tool only when the task actually involves the relevant Phaser area.

- **`PHASER_V4_NOTES.md`** — practical v3 → v4 differences and gotchas this project has hit. Check first when you suspect a v3-vs-v4 mismatch.
- **`docs/phaser-skills/<topic>/SKILL.md`** — official-style topic guides. Topics include: `physics-arcade`, `physics-matter`, `scenes`, `cameras`, `tilemaps`, `tweens`, `input-keyboard-mouse-touch`, `sprites-and-images`, `groups-and-containers`, `text-and-bitmaptext`, `time-and-timers`, `events-system`, `data-manager`, `loading-assets`, `animations`, `audio-and-sound`, `particles`, `filters-and-postfx`, `render-textures`, `geometry-and-math`, `curves-and-paths`, `actions-and-utilities`, `game-object-components`, `graphics-and-shapes`, `scale-and-responsive`, `game-setup-and-config`, `v3-to-v4-migration`, `v4-new-features`. Read the topic that matches the area you're touching.

---

## Constraints and Things to Avoid

### Hard rules (do not violate)
1. **Do NOT add payment / billing / subscription features.** That belongs in GameByTalk.
2. **Do NOT add AI features for level creation.** Levels are hand-built. AI level generation is GameByTalk's territory.
3. **Do NOT reference `Blitz Breaker` or `Mario` anywhere in code, comments, UI, asset names, or commit messages.**
4. **Do NOT design features as if a second game is launching tomorrow.** Architecture supports multi-game; product ships with only Ricochet.

### Soft guidelines
- **Prefer boring tech.** Use stack choices with clear documentation and large communities.
- **Write structured code, not "quick and dirty".** Lessons here go to GameByTalk; sloppy code teaches sloppy lessons.
- **Don't over-engineer.** No microservices, no Kubernetes. Single backend, single database, simple deploys.

---

## What "Done" Looks Like for LevelCraft v1.0

Exit criteria — when met, the founder switches focus to GameByTalk:

- ✅ Ricochet game playable in browser, with at least 20 hand-designed levels
- ✅ Level editor works, users can create and publish levels
- ✅ User registration, login, OAuth (at least one provider), email verification
- ✅ Browse levels page with sort/filter
- ✅ User profile pages showing their levels
- ✅ Like, comment, report mechanics functional
- ✅ Basic admin panel for moderating reported content
- ✅ Deployment automated, with monitoring and error alerts
- ✅ At least 100 registered users and 50 published levels

**Beyond this, LevelCraft enters maintenance mode.** Adding more features past this point is anti-goal.

---

## Lessons Document

A core deliverable, alongside the product itself, is `docs/lessons.md`. **Every time we hit a non-obvious problem, document it.** Format:

```markdown
## YYYY-MM-DD: Short title
- **Context:** What were we trying to do
- **Problem:** What went wrong / what was unexpected
- **Resolution:** How we fixed it
- **Lesson for GameByTalk:** What the takeaway is for the next product
```

This file is **as important as the code**. It's the highest-leverage output of this project.

---

## Communication Style

When working with the founder:
- The founder uses Claude Code (you) to write most code. Their leverage is **clear specs and good judgment**, not typing.
- Focus on: "what should this look like? what could go wrong? what are the edge cases?"
- Less focus on: low-level implementation details — Claude Code handles those.
- When making architecture decisions, write them up as ADRs in `docs/decisions.md`.
- When you find a non-obvious gotcha, write it to `docs/lessons.md` immediately.

---

## Current Status

- ✅ Visual style established (grayscale sci-fi robot aesthetic)
- ✅ Ricochet runtime + entity set built on Phaser 4 (player, walls, glass walls, spike blocks, directional spikes, conveyors, cannons, keys + key walls, gears, portals, turrets, teleports, cross-page exit)
- 🚧 In progress: in-game level editor (`?mode=edit`) — placement / drag-place / drag-move / gear path editing
- ⏳ Web platform (frontend + backend + database) not started yet
- ⏳ Distribution wrappers (Tauri desktop, Capacitor mobile) not started yet

---

## When You're Unsure

If a request seems to violate any of the constraints above, or if you're unsure whether something belongs in LevelCraft vs GameByTalk, **stop and ask**. The founder would rather clarify than have you build the wrong thing.
