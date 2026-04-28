# LevelCraft —— Project Context for Claude Code

> This file is the canonical project context. Claude Code should read this **before any other file** to understand what we're building, why, and what constraints apply.

---

## TL;DR

**LevelCraft** is a platform for player-created game levels. It hosts multiple game types as sub-products. The first publicly shipped game will be **LevelCraft: Ricochet** (a wall-bouncing pixel platformer).

**Current state:** A Godot project that implements the "play" part of an existing Mario-style platformer (with World 1's first 4 levels and roughly half the visual variety of Super Mario Bros 1). The "maker" (level editor) part is essentially zero. **This existing game will be archived** — see "Why Archive" below — to focus all energy on shipping Ricochet first.

**Strategic context:** LevelCraft is a **technical and operational rehearsal** for a larger product called **GameByTalk** (an AI-driven game creation tool, not in this repo). Lessons learned here will be applied there.

---

## The Four Things in This Repo's Mental Model

### 1. GameByTalk (the real long-term goal — NOT in this repo)
- AI-driven, lets users create games by chatting with an AI
- High-tech, ambitious, requires payment systems and complex AI infrastructure
- **We are NOT building this here.** Do NOT add features that "look ahead" to GameByTalk.

### 2. LevelCraft (this repo — the rehearsal product)
- A community platform where players hand-design levels using a visual editor
- Hosts multiple game types as sub-products
- Lower risk than GameByTalk, used to validate user systems / content systems / community mechanics
- **The point is not just the product itself — it's the experience and lessons that will inform GameByTalk.**

### 3. LevelCraft: Ricochet (this repo's first publicly shipped game — top priority)
- A 2D tile-based platformer with a deliberate, launch-and-stop movement mechanic
- The player is a small robot character with a 1×1 collision box, on a grid of solid tiles
- **Floor state (input accepted):** arrow keys launch the player at a constant speed in that direction. Left/right first lift the player one cell, then fly horizontally. Up flies straight up. Once launched, keyboard input is locked.
- **In-flight:** the player keeps moving until they hit something. On a wall: rebound by 1 cell, pause briefly, then fall under gravity until they land back on a floor (input accepted again).
- **Jump (Space):** vertical jump of 2 cells from the floor. During **both ascent and descent of the jump**, keyboard input is accepted — pressing any arrow key launches in that direction from the current mid-air position. So a jump lets the player choose where to launch from above floor level.
- Hazards kill the player; special tiles (sticky, teleporter, etc.) trigger their own behaviors.
- See `games/ricochet/design/design.md` for the full game design.
- **This is the first concrete game shipped on the LevelCraft platform**

### 4. The Archived Jump Game (in this repo, but on hold)
- An existing Godot project with World 1 (4 levels) of a Mario-style jumping platformer
- Implements roughly half of Super Mario Bros 1's tiles/entities/mechanics
- **Has no level editor yet** (would require significant additional work)
- **To be archived, NOT actively developed** — see "Why Archive" below

---

## Why Archive the Jump Game

The founder's analysis (which informs this decision):
- Implementing a Mario Maker-style editor for the existing jump game would be **significantly more work** than building Ricochet from scratch (jumping platformer mechanics are richer; the editor UX is more complex)
- Ricochet has a **simpler, more constrained mechanic** (4-direction dash, hits wall, stops) that maps cleanly to grid-based level data
- **Shipping a complete small game beats shipping half of an ambitious one**
- The "doubter response" public traction story is cleaner with one focused game shipped quickly
- The jump game's existing code is a learning artifact — it's not lost. It moves to `games/_archive_jump/` and can be revisited later under a proper non-Mario brand

**This is not a failure to ship the jump game. This is choosing to ship Ricochet first because it's the right product to ship now.**

---

## Naming and Branding

### Always use:
- **Platform name:** `LevelCraft`
- **First game (active development):** `LevelCraft: Ricochet` (or just `Ricochet`)
- **Archived game:** Refer to as "the archived jump game" or "the legacy platformer". **Do not give it a real product name yet** — that decision happens later if/when it's revived.

### Never use:
- ❌ `Blitz Breaker` (trademarked, copyright risk — Ricochet is inspired by but legally distinct from)
- ❌ `Mario`, `Super Mario`, `Mario Maker` (Nintendo IP — extremely litigious)
- ❌ Visual elements that resemble Mario IP (mushrooms, question blocks, pipes, koopa-like enemies, fire flowers, plumber characters)

### What's safe:
- ✅ The mechanics themselves (game mechanics are not copyrightable)
- ✅ Generic platformer elements (spikes, buttons, doors, switches)
- ✅ Original art that's clearly distinct from Nintendo and Blitz Breaker

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

- ✅ Both Ricochet and (future revival of) the archived jump game share this **visual language**
- ✅ But **asset files themselves are NOT shared** between games — each game gets its own assets, generated separately
- ✅ The founder uses ChatGPT (or similar) to generate concrete assets per game
- ✅ When prompting for new assets, reference: *"the LevelCraft style — grayscale palette (#000–#FFF), sci-fi robot/tech aesthetic, hand-illustrated 64×64 sprites with dark-to-light gradient shading"*

**Why share style but not assets:**
- Same style → unified LevelCraft platform brand (players recognize the family)
- Different assets → each game has its own visual identity within the brand
- AI-generating fresh assets per game is cheap, so duplication isn't a cost concern

**Concretely, this means:** When building Ricochet, generate **new** robot character sprites, enemy designs, and tile art in the same style as the archived jump game, but with distinct designs. Don't copy asset files from `_archive_jump/`.

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
The current single Godot project should be reorganized:

```
levelcraft/                          (monorepo root)
├── CLAUDE.md                        (this file — strategic context)
├── MIGRATION.md                     (migration steps from current state)
├── PROJECT-OVERVIEW.md              (high-level summary; supplements the existing README.md)
├── README.md                        (existing repo README — left as-is unless edited intentionally)
├── games/
│   ├── _archive_jump/               (existing project, moved here, frozen)
│   └── ricochet/                    (new Godot project, fresh start)
├── web/
│   ├── frontend/                    (planned, not started)
│   └── backend/                     (planned, not started)
├── shared/
│   └── level-schema/                (data formats — see below)
└── docs/
    ├── lessons.md                   (lessons learned, fed into GameByTalk)
    └── decisions.md                 (architecture decision records)
```

See `MIGRATION.md` for step-by-step migration instructions.

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
- **Game engine:** Godot (existing project uses it)
- **Game export target:** HTML5 (Godot's web export) so games run in browser
- **Web frontend:** TBD — recommend Next.js + TypeScript
- **Backend:** TBD — Node, Bun, or Go
- **Database:** Postgres (Supabase recommended for hosted Postgres + auth)
- **Auth:** Email + at least one OAuth (Google or Discord recommended)
- **Hosting:** Vercel (frontend), Fly.io / Railway (backend), Cloudflare R2 (assets)

---

## Constraints and Things to Avoid

### Hard rules (do not violate)
1. **Do NOT add payment / billing / subscription features.** That belongs in GameByTalk.
2. **Do NOT add AI features for level creation.** Levels are hand-built. AI level generation is GameByTalk's territory.
3. **Do NOT reference `Blitz Breaker` or `Mario` anywhere in code, comments, UI, asset names, or commit messages.**
4. **Do NOT design features as if a second game is launching tomorrow.** Architecture supports multi-game; product ships with only Ricochet.
5. **Do NOT actively develop the archived jump game.** Bug fixes acceptable if needed for archival; new features are not.
6. **Do NOT copy asset files from `_archive_jump/` into `ricochet/`.** Style is shared, asset files are not.

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

- ✅ Existing jump game has 4 levels of World 1 implemented
- ✅ Visual style established (grayscale sci-fi robot aesthetic)
- ✅ Some assets generated via ChatGPT for the jump game
- 🛑 **Existing jump game to be archived** — see "Why Archive" above
- 🚧 **Need to restructure repo into multi-game platform layout** — see `MIGRATION.md`
- 🚧 Need to start the Ricochet game (new Godot project, fresh start, new assets in shared style)
- ⏳ Web platform (frontend + backend + database) not started yet

---

## When You're Unsure

If a request seems to violate any of the constraints above, or if you're unsure whether something belongs in LevelCraft vs GameByTalk vs the archived jump game, **stop and ask**. The founder would rather clarify than have you build the wrong thing.
