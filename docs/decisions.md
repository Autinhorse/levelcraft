# Architecture Decision Records

Append-only log of non-obvious architectural decisions. Each entry captures *why* the decision was made so future contributors (and Claude Code) don't relitigate.

---

## ADR-001: Archive the existing jump game; ship Ricochet first

**Date:** 2026-04-28
**Status:** Accepted

### Context
The repo previously held a single Godot project: a Mario-style side-scrolling jumping platformer with World 1's 4 levels and roughly half of SMB1's tile/entity variety. The play half worked; the editor half was zero. Building a Mario-Maker-style editor for this game would be substantial work — jumping platformer mechanics are richer and editor UX more complex.

In parallel, we want to ship a complete game on the LevelCraft platform quickly to validate the full loop (play → edit → share → discover). LevelCraft itself is the rehearsal product for a longer-term goal (GameByTalk).

### Decision
- Archive the existing jump game in `games/_archive_jump/`. Frozen, bug-fix only, never publicly shipped under any Mario-evoking branding.
- Build **LevelCraft: Ricochet** as a fresh Godot project (`games/ricochet/`) with simpler mechanics that map cleanly onto a player-facing editor.
- Ricochet's design and assets are independent of the archived game (style is shared, files are not).

### Consequences
- Existing jump-game code is preserved as a reference, not progressed.
- Ricochet ships faster because the mechanic is simpler and the editor surface area smaller.
- Repo restructured into a multi-game monorepo (`games/`, `web/`, `shared/`, `docs/`) so adding future games and a web platform is mechanical, not architectural.
- IP hygiene: any `mario` references inside the archive get stripped (folder names, level filenames, code constants). Visual assets that resemble Mario IP stay in the archive only and are explicitly off-limits for any public/Ricochet artwork.

### Migration record
Carried out 2026-04-28. See `../MIGRATION.md` for the step-by-step plan and `_archive_jump/README.md` for the archive's own status.
