import Phaser from 'phaser';

import {
  COLOR_CANNON,
  COLOR_CANNON_BARREL,
  COLOR_COIN,
  COLOR_CONVEYOR,
  COLOR_EXIT,
  COLOR_GEAR,
  COLOR_GEAR_HUB,
  COLOR_GEAR_SPOKE,
  COLOR_GLASS,
  COLOR_GRID,
  COLOR_LASER_BEAM,
  COLOR_LASER_CANNON,
  COLOR_LASER_CANNON_BARREL,
  COLOR_LASER_HUB,
  COLOR_PLAYER,
  COLOR_SPIKE,
  COLOR_SPIKE_PLATE,
  COLOR_TELEPORT,
  COLOR_TURRET_HUB,
  COLOR_WALL,
  KEY_COLORS_DARK,
  KEY_COLORS_LIGHT,
  TILE_SIZE,
} from '../../config/feel';
import type {
  CardinalDir,
  ConveyorDir,
  Gear as GearData,
  TextLabel as TextLabelData,
} from '../../../shared/level-format/types';

// Shared layout fractions for spike + cannon-style sprites. These were
// duplicated in EditScene + PlayScene; this module owns the editor
// copy. The runtime also uses them (with its own physics anchoring)
// so cross-file divergence is a known risk if either set is tweaked.
type Rect = { x: number; y: number; w: number; h: number };
const SPIKE_LAYOUT: Record<CardinalDir, { plate: Rect; spike: Rect }> = {
  up:    { plate: { x: 0,   y: 0.5, w: 1,   h: 0.5 }, spike: { x: 0,   y: 0,   w: 1,   h: 0.5 } },
  down:  { plate: { x: 0,   y: 0,   w: 1,   h: 0.5 }, spike: { x: 0,   y: 0.5, w: 1,   h: 0.5 } },
  left:  { plate: { x: 0.5, y: 0,   w: 0.5, h: 1   }, spike: { x: 0,   y: 0,   w: 0.5, h: 1   } },
  right: { plate: { x: 0,   y: 0,   w: 0.5, h: 1   }, spike: { x: 0.5, y: 0,   w: 0.5, h: 1   } },
};
const BARREL_RECTS: Record<CardinalDir, Rect> = {
  up:    { x: 0.35, y: 0,    w: 0.30, h: 0.50 },
  down:  { x: 0.35, y: 0.50, w: 0.30, h: 0.50 },
  left:  { x: 0,    y: 0.35, w: 0.50, h: 0.30 },
  right: { x: 0.50, y: 0.35, w: 0.50, h: 0.30 },
};

// Pixel-coords of a cell's center.
export function cellCenter(col: number, row: number): { x: number; y: number } {
  return { x: (col + 0.5) * TILE_SIZE, y: (row + 0.5) * TILE_SIZE };
}

// Each draw function takes the per-page Container (so the registered
// children get torn down on the next renderPage's removeAll) and
// reads `container.scene` to access the scene factory. Pure functions
// of (container, data) — no scene-instance state required.

export function drawGridBackground(
  container: Phaser.GameObjects.Container,
  cols: number,
  rows: number,
): void {
  const scene = container.scene;
  const g = scene.add.graphics();
  g.lineStyle(1, COLOR_GRID, 1);
  for (let c = 0; c <= cols; c++) {
    g.lineBetween(c * TILE_SIZE, 0, c * TILE_SIZE, rows * TILE_SIZE);
  }
  for (let r = 0; r <= rows; r++) {
    g.lineBetween(0, r * TILE_SIZE, cols * TILE_SIZE, r * TILE_SIZE);
  }
  g.setDepth(-100);
  container.add(g);
}

export function drawWall(
  container: Phaser.GameObjects.Container,
  col: number,
  row: number,
): void {
  const { x, y } = cellCenter(col, row);
  container.add(container.scene.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_WALL));
}

export function drawCoin(
  container: Phaser.GameObjects.Container,
  col: number,
  row: number,
): void {
  const { x, y } = cellCenter(col, row);
  container.add(
    container.scene.add.rectangle(x, y, TILE_SIZE * 0.55, TILE_SIZE * 0.55, COLOR_COIN),
  );
}

export function drawGlassWall(
  container: Phaser.GameObjects.Container,
  col: number,
  row: number,
): void {
  const { x, y } = cellCenter(col, row);
  const r = container.scene.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_GLASS);
  r.setAlpha(0.55);
  container.add(r);
}

export function drawSpikeBlock(
  container: Phaser.GameObjects.Container,
  col: number,
  row: number,
): void {
  const { x, y } = cellCenter(col, row);
  const scene = container.scene;
  container.add(scene.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_SPIKE));
  container.add(
    scene.add.rectangle(x, y, TILE_SIZE / 3, TILE_SIZE / 3, COLOR_SPIKE_PLATE),
  );
}

export function drawConveyor(
  container: Phaser.GameObjects.Container,
  col: number,
  row: number,
  dir: ConveyorDir,
): void {
  const { x, y } = cellCenter(col, row);
  const scene = container.scene;
  container.add(scene.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_CONVEYOR));
  container.add(
    scene.add
      .text(x, y, dir === 'cw' ? '→' : '←', {
        color: '#ffffff',
        fontSize: '24px',
        fontStyle: 'bold',
      })
      .setOrigin(0.5),
  );
}

export function drawSpike(
  container: Phaser.GameObjects.Container,
  col: number,
  row: number,
  dir: CardinalDir,
): void {
  const tlX = col * TILE_SIZE;
  const tlY = row * TILE_SIZE;
  const layout = SPIKE_LAYOUT[dir];
  const scene = container.scene;
  container.add(
    scene.add.rectangle(
      tlX + (layout.plate.x + layout.plate.w / 2) * TILE_SIZE,
      tlY + (layout.plate.y + layout.plate.h / 2) * TILE_SIZE,
      layout.plate.w * TILE_SIZE,
      layout.plate.h * TILE_SIZE,
      COLOR_SPIKE_PLATE,
    ),
  );
  container.add(
    scene.add.rectangle(
      tlX + (layout.spike.x + layout.spike.w / 2) * TILE_SIZE,
      tlY + (layout.spike.y + layout.spike.h / 2) * TILE_SIZE,
      layout.spike.w * TILE_SIZE,
      layout.spike.h * TILE_SIZE,
      COLOR_SPIKE,
    ),
  );
}

export function drawCannon(
  container: Phaser.GameObjects.Container,
  col: number,
  row: number,
  dir: CardinalDir,
): void {
  const { x, y } = cellCenter(col, row);
  const scene = container.scene;
  container.add(scene.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_CANNON));
  const tlX = col * TILE_SIZE;
  const tlY = row * TILE_SIZE;
  const r = BARREL_RECTS[dir];
  container.add(
    scene.add.rectangle(
      tlX + (r.x + r.w / 2) * TILE_SIZE,
      tlY + (r.y + r.h / 2) * TILE_SIZE,
      r.w * TILE_SIZE,
      r.h * TILE_SIZE,
      COLOR_CANNON_BARREL,
    ),
  );
}

export function drawKeyWall(
  container: Phaser.GameObjects.Container,
  col: number,
  row: number,
  colorIdx: number,
): void {
  const { x, y } = cellCenter(col, row);
  container.add(
    container.scene.add.rectangle(
      x, y, TILE_SIZE, TILE_SIZE,
      KEY_COLORS_DARK[colorIdx] ?? 0x444444,
    ),
  );
}

export function drawKey(
  container: Phaser.GameObjects.Container,
  col: number,
  row: number,
  colorIdx: number,
): void {
  const { x, y } = cellCenter(col, row);
  container.add(
    container.scene.add.circle(x, y, TILE_SIZE * 0.25, KEY_COLORS_LIGHT[colorIdx] ?? 0xffffff),
  );
}

// `isEditing` true when this gear is the active path-edit target —
// caller (EditScene) computes via `gearEditState?.gear === g`.
export function drawGear(
  container: Phaser.GameObjects.Container,
  g: GearData,
  isEditing: boolean,
): void {
  const { x, y } = cellCenter(g.x, g.y);
  const r = (g.size * TILE_SIZE) / 2;
  const scene = container.scene;
  container.add(scene.add.circle(x, y, r, COLOR_GEAR));
  const spokes = scene.add.graphics();
  spokes.lineStyle(3, COLOR_GEAR_SPOKE, 1);
  spokes.lineBetween(x - r * 0.9, y, x + r * 0.9, y);
  spokes.lineBetween(x, y - r * 0.9, x, y + r * 0.9);
  container.add(spokes);
  container.add(scene.add.circle(x, y, r * 0.22, COLOR_GEAR_HUB));

  if (g.waypoints.length > 0) {
    const path = scene.add.graphics();
    path.lineStyle(2, COLOR_GEAR_HUB, 0.6);
    path.beginPath();
    path.moveTo(x, y);
    for (const wp of g.waypoints) {
      const c = cellCenter(wp.x, wp.y);
      path.lineTo(c.x, c.y);
    }
    if (g.closed) {
      path.lineTo(x, y);
    }
    path.strokePath();
    container.add(path);
    for (const wp of g.waypoints) {
      const c = cellCenter(wp.x, wp.y);
      container.add(scene.add.circle(c.x, c.y, TILE_SIZE * 0.1, COLOR_GEAR_HUB));
    }
  }

  if (isEditing) {
    const ring = scene.add.graphics();
    ring.lineStyle(3, 0x4ca6ff, 0.95);
    ring.strokeCircle(x, y, r + 5);
    container.add(ring);
  }
}

export function drawPortal(
  container: Phaser.GameObjects.Container,
  col: number,
  row: number,
  colorIdx: number,
): void {
  const { x, y } = cellCenter(col, row);
  const scene = container.scene;
  container.add(
    scene.add.circle(x, y, TILE_SIZE * 0.45, KEY_COLORS_DARK[colorIdx] ?? 0x444444),
  );
  container.add(
    scene.add.circle(x, y, TILE_SIZE * 0.30, KEY_COLORS_LIGHT[colorIdx] ?? 0xffffff),
  );
}

export function drawTurret(
  container: Phaser.GameObjects.Container,
  col: number,
  row: number,
): void {
  const { x, y } = cellCenter(col, row);
  const scene = container.scene;
  container.add(scene.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_CANNON));
  // Static "rest" pose — barrel pointing right at rotation 0, matching
  // the initial state Turret.barrel has before the first track update.
  container.add(
    scene.add.rectangle(
      x + TILE_SIZE * 0.30, y,
      TILE_SIZE * 0.60, TILE_SIZE * 0.20,
      COLOR_CANNON_BARREL,
    ),
  );
  container.add(scene.add.circle(x, y, TILE_SIZE * 0.16, COLOR_TURRET_HUB));
}

export function drawLaserCannon(
  container: Phaser.GameObjects.Container,
  col: number,
  row: number,
  dir: CardinalDir,
): void {
  const { x, y } = cellCenter(col, row);
  const scene = container.scene;
  container.add(scene.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_LASER_CANNON));
  const tlX = col * TILE_SIZE;
  const tlY = row * TILE_SIZE;
  const r = BARREL_RECTS[dir];
  container.add(
    scene.add.rectangle(
      tlX + (r.x + r.w / 2) * TILE_SIZE,
      tlY + (r.y + r.h / 2) * TILE_SIZE,
      r.w * TILE_SIZE,
      r.h * TILE_SIZE,
      COLOR_LASER_CANNON_BARREL,
    ),
  );
  container.add(scene.add.circle(x, y, TILE_SIZE * 0.16, COLOR_LASER_HUB));
  // Beam-direction hint — short red line projecting one tile out from
  // the cannon edge in `dir`. Faint so it doesn't clutter the editor.
  const offsetMap: Record<CardinalDir, { dx: number; dy: number }> = {
    up: { dx: 0, dy: -1 },
    down: { dx: 0, dy: 1 },
    left: { dx: -1, dy: 0 },
    right: { dx: 1, dy: 0 },
  };
  const o = offsetMap[dir];
  const hint = scene.add.graphics();
  hint.lineStyle(2, COLOR_LASER_BEAM, 0.5);
  hint.lineBetween(
    x + o.dx * TILE_SIZE * 0.5,
    y + o.dy * TILE_SIZE * 0.5,
    x + o.dx * TILE_SIZE * 1.5,
    y + o.dy * TILE_SIZE * 1.5,
  );
  container.add(hint);
}

export function drawTextLabel(
  container: Phaser.GameObjects.Container,
  tl: TextLabelData,
): void {
  const tlX = tl.x * TILE_SIZE;
  const tlY = tl.y * TILE_SIZE;
  const w = tl.width * TILE_SIZE;
  const h = tl.height * TILE_SIZE;
  const pad = 4;
  const scene = container.scene;

  // Faint dashed-style bounds outline so an empty / short label is
  // still locatable + clickable in the editor.
  const outline = scene.add.graphics();
  outline.lineStyle(1, 0x666c8c, 0.5);
  outline.strokeRect(tlX, tlY, w, h);
  container.add(outline);

  if (tl.text.length > 0) {
    const text = scene.add.text(tlX + pad, tlY + pad, tl.text, {
      color: '#cccccc',
      fontSize: `${tl.font_size ?? 16}px`,
      fontFamily: 'system-ui, -apple-system, sans-serif',
      wordWrap: { width: w - pad * 2 },
    });
    container.add(text);
  }
}

export function drawTeleport(
  container: Phaser.GameObjects.Container,
  col: number,
  row: number,
  targetPage: number,
): void {
  const { x, y } = cellCenter(col, row);
  const scene = container.scene;
  container.add(scene.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_TELEPORT));
  container.add(
    scene.add
      .text(x, y, `→${targetPage + 1}`, {
        color: '#ffffff',
        fontSize: '16px',
        fontStyle: 'bold',
      })
      .setOrigin(0.5),
  );
}

export function drawSpawn(
  container: Phaser.GameObjects.Container,
  col: number,
  row: number,
): void {
  const { x, y } = cellCenter(col, row);
  const scene = container.scene;
  // Hollow blue square + 'S' so the spawn is unmistakable in the editor.
  // (At runtime the spawn cell is empty — only the player visual sits there.)
  const r = scene.add.rectangle(x, y, TILE_SIZE, TILE_SIZE);
  r.setStrokeStyle(3, COLOR_PLAYER);
  container.add(r);
  container.add(
    scene.add
      .text(x, y, 'S', {
        color: '#4ca6ff',
        fontSize: '20px',
        fontStyle: 'bold',
      })
      .setOrigin(0.5),
  );
}

export function drawExit(
  container: Phaser.GameObjects.Container,
  col: number,
  row: number,
): void {
  const { x, y } = cellCenter(col, row);
  const scene = container.scene;
  container.add(scene.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_EXIT));
  container.add(
    scene.add
      .text(x, y, 'X', {
        color: '#ffffff',
        fontSize: '20px',
        fontStyle: 'bold',
      })
      .setOrigin(0.5),
  );
}

// Bright orange outline. Single-cell elements pass `(x*TILE, y*TILE,
// TILE_SIZE, TILE_SIZE)` as bounds; multi-cell elements (text labels)
// pass their full footprint.
export function drawSelectionBox(
  container: Phaser.GameObjects.Container,
  bounds: { x: number; y: number; w: number; h: number },
): void {
  const box = container.scene.add.graphics();
  box.lineStyle(3, 0xffaa33, 1);
  box.strokeRect(bounds.x, bounds.y, bounds.w, bounds.h);
  // Above the page renders so the highlight always reads on top of
  // its element's visual.
  box.setDepth(60);
  container.add(box);
}
