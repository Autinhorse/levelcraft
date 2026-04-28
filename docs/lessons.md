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

## 2026-04-28: Archived jump game — IP cleanup during repo restructure
- **Context:** Repo originally housed a single Godot project that was a Mario-style platformer (asset folder `sprites/mario-world/`, level files prefixed `SMB1_World*`, art style fallback constant `"mario-world"`, README written as a "I'm cloning Super Mario" narrative). When pivoting to multi-game LevelCraft layout we moved the project into `games/_archive_jump/` and stripped Mario name references.
- **Problem:** "Mario" was baked into more places than expected once you start grepping: art-style folder name + the constant referencing it, every `.png.import` file's `source_file` path, level filenames, the constructed path strings in `level_select.gd` / `main.gd` / `editor.gd`, the bundled HTML5 export's `index.js`, and narrative copy in two README files. Each layer had its own renaming consequence (rename folder ⇒ patch import files ⇒ regenerate cache; rename levels ⇒ update path-construction strings; etc.). On Windows, the move itself was blocked twice by file locks held by Photoshop and Explorer thumbnail cache.
- **Resolution:** Did the restructure as one mass move (`PowerShell Move-Item` for sprites since `git mv` and `mv` were blocked by Windows file locks even after closing the editor), then a sequence of targeted renames + sed-replaces. Kept the visual assets (sprites that resemble Mario IP) inside the archive only — the archive will never be public-shipped, the IP-risky assets just exist as a learning artifact.
- **Lesson for GameByTalk:** Any project that "looks like" a known IP needs **upfront naming hygiene** — pick a non-trademark folder name and game name from day 1. Retroactive cleanup is significantly more annoying than getting it right at project init: every cached path, build artifact, and import file has to be rewritten. Cost of doing it wrong scales with project age and asset count. Add a CI grep check (`grep -i mario .` returning hits = build fail) the moment a project picks its real name.
