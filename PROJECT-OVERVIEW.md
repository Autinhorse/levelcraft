# Project Overview — LevelCraft

> This document supplements the repo's `README.md` with strategic and structural context. The `README.md` describes what the code is now; this document describes what we're building toward and why.

## What This Repo Is

This repo is becoming the codebase for **LevelCraft** — a platform for player-created game levels, hosting multiple game types as sub-products.

## Status

- Currently contains an existing Godot project for a Mario-style jumping platformer (World 1, 4 levels, ~half of SMB1's variety, no level editor)
- About to undergo restructure into a multi-game platform layout
- The first publicly shipped game will be **LevelCraft: Ricochet** — a wall-bouncing pixel platformer
- The existing jump game will be archived (frozen, not deleted) to focus on Ricochet

## Why LevelCraft

The founder is building toward a larger product, **GameByTalk** (an AI-driven game creation tool — not in this repo). LevelCraft is a deliberate stepping stone — a simpler product that lets us validate user systems, content moderation, and community mechanics before tackling GameByTalk's harder problems (AI infrastructure, payments, complex UX).

**Lessons learned from LevelCraft will be applied to GameByTalk.** That's why `docs/lessons.md` is treated as a first-class deliverable alongside the code.

## Target Project Layout

```
levelcraft/
├── games/
│   ├── ricochet/       The first game — wall-bouncing pixel platformer
│   └── _archive_jump/  Earlier Mario-style platformer prototype (archived)
├── web/
│   ├── frontend/       Platform website (planned)
│   └── backend/        API server (planned)
├── shared/
│   └── level-schema/   Level data formats shared between games and platform
└── docs/
    ├── lessons.md      Lessons learned (high priority — the seed corpus for GameByTalk)
    └── decisions.md    Architecture decision records
```

## For Anyone Reading This Repo

- **For Claude Code:** read `CLAUDE.md` for the canonical project context
- **For migration steps:** read `MIGRATION.md`
- **For technical/code-level info:** the existing `README.md` and any per-directory READMEs

## Constraints to Remember

- This is **not** GameByTalk. Don't add AI level-generation or payment features here.
- No `Mario`, `Blitz Breaker`, or other IP-risky names anywhere in code, comments, or assets.
- The archived jump game is on hold — bug fixes only, no new features.
- Visual style is shared across LevelCraft games (grayscale sci-fi robot aesthetic), but asset files are generated separately per game.

See `CLAUDE.md` for the full set of rules.
