# Shared

Cross-game / cross-stack shared assets and definitions.

- `level-schema/` — JSON schemas for level data, one per game (`ricochet.md`, etc.). The platform's `levels.data` JSONB column accepts any of these, dispatched by `game_type`.
