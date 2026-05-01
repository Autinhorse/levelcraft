import type { LevelData } from './types';

// Validates a parsed JSON value matches the bare-minimum LevelData shape
// the runtime needs. Strict on `pages[].tiles` and `pages[].spawn` (the
// game can't run without these); permissive on everything else (optional
// element arrays are validated lazily by their respective consumers, so
// this loader stays useful as the schema evolves).
//
// Throws Error with a clear "where + what" message on failure. Returns
// the input cast to LevelData on success — callers should treat the
// returned value as read-only.
export function validateLevel(data: unknown, source: string): LevelData {
  if (typeof data !== 'object' || data === null) {
    throw new Error(`Level "${source}": top-level must be a JSON object`);
  }
  const obj = data as Record<string, unknown>;

  if (!Array.isArray(obj.pages) || obj.pages.length === 0) {
    throw new Error(`Level "${source}": "pages" must be a non-empty array`);
  }

  for (let i = 0; i < obj.pages.length; i++) {
    const page = obj.pages[i];
    if (typeof page !== 'object' || page === null) {
      throw new Error(`Level "${source}": page ${i} must be an object`);
    }
    const p = page as Record<string, unknown>;

    if (!Array.isArray(p.tiles) || p.tiles.length === 0) {
      throw new Error(`Level "${source}": page ${i} "tiles" must be a non-empty array`);
    }
    const firstRow = p.tiles[0];
    if (typeof firstRow !== 'string') {
      throw new Error(`Level "${source}": page ${i} "tiles[0]" must be a string`);
    }
    const cols = firstRow.length;
    for (let r = 0; r < p.tiles.length; r++) {
      const row = p.tiles[r];
      if (typeof row !== 'string') {
        throw new Error(`Level "${source}": page ${i} "tiles[${r}]" must be a string`);
      }
      if (row.length !== cols) {
        throw new Error(
          `Level "${source}": page ${i} tile rows must all be length ${cols} ` +
          `(row ${r} is ${row.length})`,
        );
      }
    }

    const spawn = p.spawn as Record<string, unknown> | undefined;
    if (!spawn || typeof spawn.x !== 'number' || typeof spawn.y !== 'number') {
      throw new Error(`Level "${source}": page ${i} "spawn" must have numeric x and y`);
    }
  }

  return obj as unknown as LevelData;
}
