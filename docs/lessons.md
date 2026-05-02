# Lessons Learned

This file is the highest-leverage output of LevelCraft, alongside the product itself. **Every lesson learned here will be applied to GameByTalk.** Update this whenever something non-obvious happens.

## Format

```markdown
## YYYY-MM-DD: Short title
- **Context:** What were we trying to do
- **Problem:** What went wrong / what was unexpected
- **Resolution:** How we fixed it
- **Lesson for GameByTalk:** What the takeaway is for the next product
```

## Categories worth documenting

- **Auth & user management:** OAuth edge cases, email deliverability, account merging, password resets, session management
- **Content management:** Validation, versioning, deletion cascades, search/discovery
- **Community:** Moderation workflows, troll handling, reporting, evidence handling
- **Performance & scale:** Where things got slow, what helped
- **DevOps & deployment:** Build pipelines, environment config, secret management
- **User behavior surprises:** "I thought users would do X but they did Y"
- **Cost surprises:** Bills that came in higher than expected, why
- **IP / branding:** Naming gotchas, asset cleanup, anything legal-ish

---

## Entries

<!-- Add new entries above this line, newest first -->

## 2026-05-02: Phaser 4 — `StaticBody.updateFromGameObject()` is incompatible with `Container`
- **Context:** Porting the Godot game to Phaser 4 + TypeScript. `Turret` is a multi-part entity (axis-aligned base + rotating barrel sub-container), so it had to be a `Phaser.GameObjects.Container`. To give it a wall-like collider, we did the same dance we use for plain Rectangle entities: `physics.add.existing(this, true)` → `body.setSize(TILE_SIZE, TILE_SIZE)` → `body.updateFromGameObject()`.
- **Problem:** Scene crashed at construction with `TypeError: gameObject.getTopLeft is not a function`. The crash happened during `create()`, so the *entire* scene failed to set up — no HUD, no input, no rendered player, no bullets — making it look like a complete app failure rather than a single-entity bug. `StaticBody.updateFromGameObject()` in Phaser 4 calls `gameObject.getTopLeft()` to position the body, but `Container` doesn't implement `getTopLeft` / `getCenter` / `displayWidth` (those are Sprite/Rectangle/Shape methods). Same `physics.add.existing(this, true)` call on a `Rectangle` works fine — the helper is only valid for game objects with the AABB-introspection methods.
- **Resolution:** Don't call `updateFromGameObject()` for Container-hosted static bodies. Position the body manually instead: `this.body.position.set(this.x - w/2, this.y - h/2)` after `setSize`. For *circular* static bodies on a Container (Portal, Gear), `body.setCircle(r, -r, -r)` already sets the body geometry directly with no introspection step needed, so no fix required there.
- **Lesson for GameByTalk:** When a single entity's constructor throws inside a scene's `create()`, the symptom is "the whole game is broken" — no HUD, no input, no anything. The fix is one line in one file, but the visible blast radius makes it feel catastrophic. Two takeaways: **(1)** wrap each entity-builder in try/catch in dev builds and log "skipped X due to error" so the rest of the scene still comes up — bug reports become "this entity is missing" instead of "everything is broken". **(2)** Phaser-style framework helpers that take a generic `GameObject` argument often quietly assume Sprite-shaped duck-typing; whenever you host a body on something exotic (Container, Group, custom class), test the body-position path explicitly, don't trust that "it worked for Rectangle" generalises.

## 2026-04-28: Archived jump game — IP cleanup during repo restructure
- **Context:** Repo originally housed a single Godot project that was a Mario-style platformer (asset folder `sprites/mario-world/`, level files prefixed `SMB1_World*`, art style fallback constant `"mario-world"`, README written as a "I'm cloning Super Mario" narrative). When pivoting to multi-game LevelCraft layout we moved the project into `games/_archive_jump/` and stripped Mario name references.
- **Problem:** "Mario" was baked into more places than expected once you start grepping: art-style folder name + the constant referencing it, every `.png.import` file's `source_file` path, level filenames, the constructed path strings in `level_select.gd` / `main.gd` / `editor.gd`, the bundled HTML5 export's `index.js`, and narrative copy in two README files. Each layer had its own renaming consequence (rename folder ⇒ patch import files ⇒ regenerate cache; rename levels ⇒ update path-construction strings; etc.). On Windows, the move itself was blocked twice by file locks held by Photoshop and Explorer thumbnail cache.
- **Resolution:** Did the restructure as one mass move (`PowerShell Move-Item` for sprites since `git mv` and `mv` were blocked by Windows file locks even after closing the editor), then a sequence of targeted renames + sed-replaces. Kept the visual assets (sprites that resemble Mario IP) inside the archive only — the archive will never be public-shipped, the IP-risky assets just exist as a learning artifact.
- **Lesson for GameByTalk:** Any project that "looks like" a known IP needs **upfront naming hygiene** — pick a non-trademark folder name and game name from day 1. Retroactive cleanup is significantly more annoying than getting it right at project init: every cached path, build artifact, and import file has to be rewritten. Cost of doing it wrong scales with project age and asset count. Add a CI grep check (`grep -i mario .` returning hits = build fail) the moment a project picks its real name.
