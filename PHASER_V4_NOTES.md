# Phaser v4 Notes — v3 → v4 Differences and Gotchas

This document tracks the practical differences between Phaser 3 and Phaser 4 that affect this project. It exists because most online tutorials and AI training data describe v3, but **this project uses v4**.

For the authoritative reference, see `docs/phaser-skills/v3-to-v4-migration/SKILL.md` (copied from the official Phaser repo) and the [v4 Migration Guide](https://github.com/phaserjs/phaser/blob/master/changelog/v4/4.0/MIGRATION-GUIDE.md).

---

## Quick Sanity Check

If you're reading code and want to know "is this v3 or v4?", look for these tells:

| If you see... | It's likely... |
|---|---|
| `import * as Phaser from 'phaser'` | v3 (or v4 before 4.1.0) |
| `import Phaser from 'phaser'` (default import) | v4 (4.1.0+) |
| `sprite.setTintFill(0xff0000)` | v3 — replace with v4 equivalent |
| `sprite.setTintMode(...)` | v4 |
| `new Phaser.Geom.Point(x, y)` | v3 — class removed in v4 |
| `new Phaser.Math.Vector2(x, y)` | v4 (works in v3 too, but v4 standard) |
| `pipeline` references in rendering code | v3 — v4 uses RenderNode |
| `TilemapGPULayer` | v4 only |
| `SpriteGPULayer` | v4 only |
| `setLighting(true)` on a sprite | v4 only |

---

## Breaking Changes That Affect Us

### 1. Renderer Architecture (Mostly Invisible to Us)

v3's pipeline system has been replaced with a RenderNode architecture. Most game code doesn't touch this directly. **You only need to care if you were writing custom rendering pipelines** — we're not.

**What this means in practice:** if you find a v3 tutorial that does `this.renderer.pipelines.something`, that code will not work in v4. Find a v4 equivalent or rewrite without custom pipeline manipulation.

### 2. Tint System

This is the most common breaking change you'll hit when copying v3 code.

**v3:**
```typescript
sprite.setTint(0xff0000);       // multiply tint
sprite.setTintFill(0xff0000);   // fill tint (different mode)
```

**v4:**
```typescript
sprite.setTint(0xff0000);                          // sets color only
sprite.setTintMode(Phaser.TintMode.MULTIPLY);      // sets mode separately
// or any of: MULTIPLY, FILL, ADD, SCREEN, OVERLAY, HARD_LIGHT
```

`setTintFill()` still exists for compatibility but **does nothing**. Always use `setTintMode()` to change the blending behavior.

### 3. FX and Masks Are Now Filters

In v3, FX (post-processing effects) and Masks were two separate systems with limitations on what they could be applied to.

**v4:** Both are unified into a single Filter system. Filters can be applied to any GameObject or Camera with no restrictions.

**v3:**
```typescript
sprite.preFX.addBloom();
sprite.setMask(maskGraphics.createGeometryMask());
```

**v4:**
```typescript
sprite.filters.internal.add(new Phaser.Filters.Bloom());
sprite.filters.internal.add(new Phaser.Filters.Mask({ source: maskGraphics }));
```

If you find v3 code using `preFX`, `postFX`, `setMask`, `clearMask`, etc., look up the Filter equivalent in `docs/phaser-skills/filters-and-postfx/SKILL.md`.

### 4. Removed Classes

These classes existed in v3 and are gone in v4:

| Removed | Use instead |
|---|---|
| `Phaser.Geom.Point` | `Phaser.Math.Vector2` |
| `Phaser.GameObjects.Mesh` | (consider Stamp or Shader for alternatives) |
| `Phaser.Display.Masks.BitmapMask` | `Phaser.Filters.Mask` |
| Phaser's own `Set` data structure | Native browser `Set` |

If you see a v3 code sample using these, replace before committing.

### 5. ESM Imports

**v3 / early v4 hack:**
```typescript
import * as Phaser from 'phaser';
```

**v4.1.0+:**
```typescript
import Phaser from 'phaser';   // default export now works correctly
```

The fix landed in v4.1.0 ("Salusa") — earlier v4 builds had a buggy ESM export. We pin to 4.1.0+ in `package.json` so this is fine.

If you need `window.Phaser` for some reason (legacy plugin), set it manually after import:
```typescript
import Phaser from 'phaser';
window.Phaser = Phaser;
```

### 6. Canvas Renderer Is Deprecated

v4's Canvas renderer still exists but is deprecated and missing most v4 features (Filters, GPU layers, etc.). **Always use WebGL.** Set `type: Phaser.WEBGL` (or `Phaser.AUTO`) in game config.

### 7. No Direct WebGL Calls

In v3 you could occasionally drop down to raw `gl.*` calls. In v4, doing so will desync Phaser's internal WebGL state wrapper and cause weird bugs. If you need direct WebGL, use an Extern GameObject which resets state cleanly.

---

## v4 New Features Worth Knowing About

These don't break v3 code but are useful for our project:

### TilemapGPULayer

v4 ships a special tilemap renderer that draws an entire layer as a single GPU quad. It's much faster than `TilemapLayer` for large static maps.

**Use it for:** the game runtime's static level geometry.
**Don't use it for:** the level editor (it's optimized for static content; tile edits require regenerating the GPU texture). Also doesn't support isometric/hexagonal layers — orthographic only.

```typescript
// gpu = true makes it a TilemapGPULayer
const layer = map.createLayer('ground', tileset, 0, 0, true);
```

Limits to know:
- Single tileset per layer (single texture image)
- Max 4096×4096 tiles
- Orthographic tilemaps only

### SpriteGPULayer

For rendering thousands of sprites in a single draw call. Probably overkill for our platformer's main entities, but useful for particle-heavy effects, bullet hell sections, large numbers of background decorations.

### `setLighting(true)`

v4's lighting system is much simpler than v3's. To enable lighting on a sprite:
```typescript
sprite.setLighting(true);
```
Self-shadows from texture brightness work too. Configure scene-wide lighting via the Light Manager.

### New Filters (post-processing)

Bloom, Glow, Shadow, Pixelate, ColorMatrix, Vignette, Wipe, ImageLight, GradientMap, Quantize, Blend, Key (chroma key), and more. Useful for game feel: hit flashes, level-complete transitions, weather, etc.

---

## Things That DID NOT Change (Most Code "Just Works")

The following v3 patterns work the same in v4. Don't waste time looking for differences here:

- Scene lifecycle: `init`, `preload`, `create`, `update` — identical
- Loading assets: `this.load.image()`, `this.load.tilemapTiledJSON()`, `this.load.spritesheet()`, etc. — identical
- Arcade Physics body API: `setVelocity`, `setGravity`, `setCollideWorldBounds`, `body.touching`, `body.blocked` — identical
- Tilemap creation from Tiled JSON: `this.make.tilemap({ key: 'level' })`, `addTilesetImage`, `createLayer` — identical (just the optional `gpu` parameter is new)
- Collision setup: `this.physics.add.collider`, `setCollisionBetween` — identical
- Camera: `startFollow`, `setBounds`, `setZoom` — identical
- Input: `this.input.keyboard.createCursorKeys()`, `this.input.on('pointerdown', ...)` — identical
- Animations: `this.anims.create`, `play`, etc. — identical
- Tweens: `this.tweens.add` — identical
- Containers, Groups — identical

**Roughly 80% of Phaser code translates 1:1 between v3 and v4.** The breaking changes are concentrated in rendering, FX/masks, and the tint system.

---

## Project-Specific Gotchas (Add as We Hit Them)

> Add new entries here as we encounter them. Each entry should describe the symptom, the root cause, and the fix.

### (template — delete this section once we have real entries)

**Symptom:** [what went wrong]
**Cause:** [v3 vs v4 difference, or v4-specific quirk]
**Fix:** [what we did]
**Date / commit:** [when we hit it]

---

## When in Doubt

1. Read the relevant file in `docs/phaser-skills/`.
2. Check the [official v4 migration guide](https://github.com/phaserjs/phaser/blob/master/changelog/v4/4.0/MIGRATION-GUIDE.md).
3. Check the [v4 API docs](https://docs.phaser.io) (these are v4, not v3).
4. As a last resort, check the [v4.0.0 changelog](https://github.com/phaserjs/phaser/blob/master/changelog/v4/4.0/CHANGELOG-v4.0.0.md).

Stack Overflow and old blog tutorials are mostly v3 — treat them as starting points, not authoritative answers.
