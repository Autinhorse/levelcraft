import Phaser from 'phaser';

import {
  COLOR_BACKGROUND,
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
  DEFAULT_LEVEL_URL,
  KEY_COLORS_DARK,
  KEY_COLORS_LIGHT,
  TILE_SIZE,
} from '../config/feel';
import { validateLevel } from '../../shared/level-format/load';
import type {
  CardinalDir,
  Cannon as CannonData,
  Conveyor as ConveyorData,
  ConveyorDir,
  Gear as GearData,
  GlassWall as GlassWallData,
  Key as KeyData,
  KeyWall as KeyWallData,
  LaserCannon as LaserCannonData,
  LaserRotateMode,
  LevelData,
  PageData,
  Spike as SpikeData,
  SpikeBlock as SpikeBlockData,
  Teleport as TeleportData,
  TextLabel as TextLabelData,
  Turret as TurretData,
} from '../../shared/level-format/types';

// Selection state: a tagged reference into the level data so mutations
// flow straight back into the saved JSON. The `ref` is the actual
// element object inside its page array, NOT a copy — drag-move works
// transparently because moveElementAt mutates ref.x / ref.y in place.
type SelectedElement =
  | { kind: 'glass_wall'; ref: GlassWallData }
  | { kind: 'spike_block'; ref: SpikeBlockData }
  | { kind: 'spike'; ref: SpikeData }
  | { kind: 'conveyor'; ref: ConveyorData }
  | { kind: 'cannon'; ref: CannonData }
  | { kind: 'turret'; ref: TurretData }
  | { kind: 'gear'; ref: GearData }
  | { kind: 'key'; ref: KeyData }
  | { kind: 'key_wall'; ref: KeyWallData }
  | { kind: 'teleport'; ref: TeleportData }
  | { kind: 'laser_cannon'; ref: LaserCannonData }
  | { kind: 'text_label'; ref: TextLabelData };

const LEVEL_KEY = 'editor-level';

// One ID per placeable thing — direction / color / target-page now live
// in `toolParams` instead of being baked into the tool name. Selecting a
// tool reveals its params panel; param changes update the persistent
// state and the next click uses those values. `select` is a non-placement
// mode: clicks pick up an existing element to drag-and-drop.
type ToolId =
  | 'select'
  | 'wall' | 'coin' | 'glass' | 'spike_block'
  | 'spike' | 'conveyor' | 'cannon' | 'turret' | 'gear' | 'laser_cannon'
  | 'portal' | 'key' | 'key_wall' | 'teleport' | 'text'
  | 'spawn' | 'exit' | 'eraser';

// Tools that support hold-and-drag continuous action. Eraser drags to
// wipe a streak; the placement entries are limited to simple,
// directionless / single-color elements where dragging has an obvious
// meaning (paint a row of walls). Tools with params (cannon direction,
// key color, teleport target) stay click-only so the user doesn't
// accidentally paint a wrong-direction streak.
const DRAG_ENABLED_TOOLS: ReadonlySet<ToolId> = new Set<ToolId>([
  'wall', 'coin', 'glass', 'spike', 'eraser',
]);

// Per-tool sticky params: each entry remembers what the user last picked
// in that tool's params panel. Only listed tools that actually have
// editable params; the rest (wall, coin, glass, spike_block, turret,
// gear, spawn, exit, eraser) place with hard-coded defaults today.
interface ToolParamsState {
  spike: CardinalDir;
  cannon: CardinalDir;
  conveyor: ConveyorDir;
  portal: number;       // 0..KEY_COLORS_LIGHT.length-1
  key: number;
  key_wall: number;
  teleport: number;     // target page index
  laser_cannon: {
    dir: CardinalDir;
    rotate: LaserRotateMode;
    duration: number;   // seconds; 0 = continuous, else stepped 0.5
    downtime: number;   // seconds; stepped 0.5
  };
  text: {
    width: number;     // cells, integer >= 1
    height: number;    // cells, integer >= 1
  };
}

// Per-tool defaults applied at placement time. 13a-3 will add a params
// panel to override these per-instance after placement.
const DEFAULT_GLASS_DELAY = 1.0;
const DEFAULT_CANNON_PERIOD = 2.0;
const DEFAULT_CANNON_BULLET_SPEED = 8.0;
const DEFAULT_TURRET_PERIOD = 2.0;
const DEFAULT_TURRET_BULLET_SPEED = 8.0;
const DEFAULT_GEAR_SIZE = 2;
const DEFAULT_GEAR_SPEED = 3.0;
const DEFAULT_GEAR_SPIN = 4.0;

// Spike + barrel layouts duplicated from PlayScene for v1 — the editor
// only needs the visual shape, not the physics layout. Phase 13b can lift
// these into a shared draw module once the editor's drawing surface is
// stable; premature extraction now would couple two files that are still
// in flux.
type Rect = { x: number; y: number; w: number; h: number };
const SPIKE_LAYOUT: Record<CardinalDir, { plate: Rect; spike: Rect }> = {
  up:    { plate: { x: 0,   y: 0.8, w: 1,   h: 0.2 }, spike: { x: 0,   y: 0.4, w: 1,   h: 0.4 } },
  down:  { plate: { x: 0,   y: 0,   w: 1,   h: 0.2 }, spike: { x: 0,   y: 0.2, w: 1,   h: 0.4 } },
  left:  { plate: { x: 0.8, y: 0,   w: 0.2, h: 1   }, spike: { x: 0.4, y: 0,   w: 0.4, h: 1   } },
  right: { plate: { x: 0,   y: 0,   w: 0.2, h: 1   }, spike: { x: 0,   y: 0,   w: 0.4, h: 1   } },
};
const BARREL_RECTS: Record<CardinalDir, Rect> = {
  up:    { x: 0.35, y: 0,    w: 0.30, h: 0.50 },
  down:  { x: 0.35, y: 0.50, w: 0.30, h: 0.50 },
  left:  { x: 0,    y: 0.35, w: 0.50, h: 0.30 },
  right: { x: 0.50, y: 0.35, w: 0.50, h: 0.30 },
};

// Phase 13a-1 — level editor scaffolding. Renders the loaded level
// non-interactively (no click-to-place yet — that's 13a-2). What works:
//   - Boot via ?mode=edit
//   - Page navigation (prev / next)
//   - Save level → JSON download
//   - Load level → file picker
//   - Play → hands the in-memory level to PlayScene with no save round-trip
export class EditScene extends Phaser.Scene {
  private level!: LevelData;
  private currentPageIndex = 0;
  // Container holds everything we draw for the current page so a page
  // switch is `removeAll(true)` instead of tracking each game object.
  private pageRoot!: Phaser.GameObjects.Container;
  private palette: HTMLDivElement | null = null;
  private paramsPanel: HTMLDivElement | null = null;
  private pageLabel: HTMLSpanElement | null = null;
  private fileLabel: HTMLSpanElement | null = null;
  private selectedTool: ToolId | null = null;
  private toolParams: ToolParamsState = {
    spike: 'up',
    cannon: 'right',
    conveyor: 'cw',
    portal: 0,
    key: 0,
    key_wall: 0,
    teleport: 1,  // sensible default: send to page 2; clamped on apply
    laser_cannon: { dir: 'right', rotate: 'none', duration: 3.0, downtime: 3.0 },
    text: { width: 4, height: 2 },
  };

  // Drag-to-paint: set on pointerdown when the active tool supports it
  // (DRAG_PLACEABLE_TOOLS), updated on pointermove to skip cells already
  // painted in this drag, cleared on pointerup. lastCol/lastRow start at
  // the cell we just placed in pointerdown so we don't double-place there.
  private placementDragState: { lastCol: number; lastRow: number } | null = null;

  // Select-tool gesture tracker. `dragGhost` stays null until the
  // pointer leaves the start cell — its presence is the signal "this
  // is a drag, not a click". On pointerup we route to drag-completion
  // (move element) if the ghost was created, or to click-handling
  // (gear-path edit ops) when the up cell matches the down cell.
  // Cleared on pointerup, scene shutdown, tool change, or page change.
  private selectGesture: {
    start: { col: number; row: number };
    dragGhost: Phaser.GameObjects.Rectangle | null;
  } | null = null;

  // Gear path editor — a sub-state of the Select tool. Set when the
  // user clicks (no drag) on an existing gear in Select mode. While
  // active, clicks on empty cells push waypoints, clicks on a different
  // gear switch the edit target, and clicking the current gear's home
  // closes the loop and exits. Reset on tool switch, page change,
  // erase of the gear, or the "Done (open)" action.
  private gearEditState: { gear: GearData } | null = null;

  // Currently-selected element for instance-level editing. Set on a
  // single click in Select mode, cleared on tool switch, page change,
  // erase of the selected element, or click on an empty cell. Drives
  // both the bounding-box highlight and the per-type params panel.
  private selectedElement: SelectedElement | null = null;

  // Path the level was loaded from — also where Save writes back via
  // the dev-server `/api/save-level` endpoint. null means "no known
  // disk path" (e.g. legacy boot with no levelPath); Save degrades to
  // a download in that case so changes aren't lost.
  private levelPath: string | null = null;

  constructor() {
    super('EditScene');
  }

  init(data?: { level?: LevelData; pageIndex?: number; levelPath?: string }): void {
    if (data?.level) {
      this.level = data.level;
    }
    this.currentPageIndex = data?.pageIndex ?? 0;
    this.levelPath = data?.levelPath ?? null;
  }

  preload(): void {
    // Only fetch a level file when not handed one via init() (e.g. the
    // editor's Play hand-off carries the in-memory level back). When a
    // levelPath was provided we load that file specifically; otherwise
    // we fall back to the legacy default (kept around as a sandbox).
    if (!this.level) {
      const url = this.levelPath ?? DEFAULT_LEVEL_URL;
      this.load.json(LEVEL_KEY, url);
    }
  }

  create(): void {
    this.cameras.main.setBackgroundColor(COLOR_BACKGROUND);

    if (!this.level) {
      const raw = this.cache.json.get(LEVEL_KEY) as unknown;
      this.level = validateLevel(raw, DEFAULT_LEVEL_URL);
    }

    this.pageRoot = this.add.container(0, 0);
    this.renderPage();
    this.buildPalette();

    // Cell click → apply selected tool. Phaser's `pointer.worldX/Y` already
    // factors in camera scroll + canvas-fit scaling, so we get true world
    // coords without manual conversion.
    this.input.on(Phaser.Input.Events.POINTER_DOWN, (p: Phaser.Input.Pointer) =>
      this.onPointerDown(p),
    );
    this.input.on(Phaser.Input.Events.POINTER_MOVE, (p: Phaser.Input.Pointer) =>
      this.onPointerMove(p),
    );
    this.input.on(Phaser.Input.Events.POINTER_UP, (p: Phaser.Input.Pointer) =>
      this.onPointerUp(p),
    );

    // Tear down DOM palette on scene exit so it doesn't linger over
    // PlayScene (or persist after a hot reload).
    this.events.once(Phaser.Scenes.Events.SHUTDOWN, () => {
      this.cancelDrag();
      this.destroyPalette();
    });
    this.events.once(Phaser.Scenes.Events.DESTROY, () => {
      this.cancelDrag();
      this.destroyPalette();
    });
  }

  // --- rendering ---------------------------------------------------------

  private renderPage(): void {
    this.pageRoot.removeAll(true);
    const page = this.level.pages[this.currentPageIndex];
    if (!page) return;

    const cols = page.tiles[0]!.length;
    const rows = page.tiles.length;
    const offsetX = (this.scale.gameSize.width - cols * TILE_SIZE) / 2;
    const offsetY = (this.scale.gameSize.height - rows * TILE_SIZE) / 2;
    this.cameras.main.setScroll(-offsetX, -offsetY);

    this.drawGridBackground(cols, rows);

    for (let r = 0; r < rows; r++) {
      const row = page.tiles[r]!;
      for (let c = 0; c < row.length; c++) {
        const ch = row.charAt(c);
        if (ch === 'W') this.drawWall(c, r);
        else if (ch === 'C') this.drawCoin(c, r);
      }
    }

    page.glass_walls?.forEach((g) => this.drawGlassWall(g.x, g.y));
    page.spike_blocks?.forEach((s) => this.drawSpikeBlock(s.x, s.y));
    page.conveyors?.forEach((c) => this.drawConveyor(c.x, c.y, c.dir));
    page.spikes?.forEach((s) => this.drawSpike(s.x, s.y, s.dir));
    page.cannons?.forEach((c) => this.drawCannon(c.x, c.y, c.dir));
    page.key_walls?.forEach((k) => this.drawKeyWall(k.x, k.y, k.color));
    page.keys?.forEach((k) => this.drawKey(k.x, k.y, k.color));
    page.gears?.forEach((g) => this.drawGear(g));
    page.portals?.forEach((p) =>
      p.points.forEach((pt) => this.drawPortal(pt.x, pt.y, p.color)),
    );
    page.turrets?.forEach((t) => this.drawTurret(t.x, t.y));
    page.laser_cannons?.forEach((l) => this.drawLaserCannon(l.x, l.y, l.dir));
    page.text_labels?.forEach((tl) => this.drawTextLabel(tl));
    page.teleports?.forEach((t) => this.drawTeleport(t.x, t.y, t.target_page));

    this.drawSpawn(page.spawn.x, page.spawn.y);
    if (this.level.exit.page === this.currentPageIndex) {
      this.drawExit(this.level.exit.x, this.level.exit.y);
    }
    this.drawSelectionBox();
  }

  // Bright orange outline around the selected element's anchor cell.
  // For multi-cell elements (e.g. size-2+ gears) this shows the home
  // cell only; that's intentional — the highlight names the cell the
  // user clicked, which is also the drag origin and the data anchor.
  private drawSelectionBox(): void {
    if (!this.selectedElement) return;
    const sel = this.selectedElement;
    // Multi-cell elements (text_label) outline their full bounds; the
    // single-cell default outlines just the anchor cell.
    const w = sel.kind === 'text_label' ? sel.ref.width * TILE_SIZE : TILE_SIZE;
    const h = sel.kind === 'text_label' ? sel.ref.height * TILE_SIZE : TILE_SIZE;
    const tlX = sel.ref.x * TILE_SIZE;
    const tlY = sel.ref.y * TILE_SIZE;
    const box = this.add.graphics();
    box.lineStyle(3, 0xffaa33, 1);
    box.strokeRect(tlX, tlY, w, h);
    // Above the page renders so the highlight always reads on top of
    // its element's visual.
    box.setDepth(60);
    this.register(box);
  }

  // Adds a child to the per-page container so the next renderPage() can
  // tear it down with removeAll(true) (which destroys children, not just
  // detaches them).
  private register(obj: Phaser.GameObjects.GameObject): void {
    this.pageRoot.add(obj);
  }

  private cellCenter(col: number, row: number): { x: number; y: number } {
    return { x: (col + 0.5) * TILE_SIZE, y: (row + 0.5) * TILE_SIZE };
  }

  private drawGridBackground(cols: number, rows: number): void {
    const g = this.add.graphics();
    g.lineStyle(1, COLOR_GRID, 1);
    for (let c = 0; c <= cols; c++) {
      g.lineBetween(c * TILE_SIZE, 0, c * TILE_SIZE, rows * TILE_SIZE);
    }
    for (let r = 0; r <= rows; r++) {
      g.lineBetween(0, r * TILE_SIZE, cols * TILE_SIZE, r * TILE_SIZE);
    }
    g.setDepth(-100);
    this.register(g);
  }

  private drawWall(col: number, row: number): void {
    const { x, y } = this.cellCenter(col, row);
    this.register(this.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_WALL));
  }

  private drawCoin(col: number, row: number): void {
    const { x, y } = this.cellCenter(col, row);
    this.register(
      this.add.rectangle(x, y, TILE_SIZE * 0.55, TILE_SIZE * 0.55, COLOR_COIN),
    );
  }

  private drawGlassWall(col: number, row: number): void {
    const { x, y } = this.cellCenter(col, row);
    const r = this.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_GLASS);
    r.setAlpha(0.55);
    this.register(r);
  }

  private drawSpikeBlock(col: number, row: number): void {
    const { x, y } = this.cellCenter(col, row);
    this.register(this.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_SPIKE));
    this.register(
      this.add.rectangle(x, y, TILE_SIZE / 3, TILE_SIZE / 3, COLOR_SPIKE_PLATE),
    );
  }

  private drawConveyor(col: number, row: number, dir: ConveyorDir): void {
    const { x, y } = this.cellCenter(col, row);
    this.register(this.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_CONVEYOR));
    this.register(
      this.add
        .text(x, y, dir === 'cw' ? '→' : '←', {
          color: '#ffffff',
          fontSize: '24px',
          fontStyle: 'bold',
        })
        .setOrigin(0.5),
    );
  }

  private drawSpike(col: number, row: number, dir: CardinalDir): void {
    const tlX = col * TILE_SIZE;
    const tlY = row * TILE_SIZE;
    const layout = SPIKE_LAYOUT[dir];
    this.register(
      this.add.rectangle(
        tlX + (layout.plate.x + layout.plate.w / 2) * TILE_SIZE,
        tlY + (layout.plate.y + layout.plate.h / 2) * TILE_SIZE,
        layout.plate.w * TILE_SIZE,
        layout.plate.h * TILE_SIZE,
        COLOR_SPIKE_PLATE,
      ),
    );
    this.register(
      this.add.rectangle(
        tlX + (layout.spike.x + layout.spike.w / 2) * TILE_SIZE,
        tlY + (layout.spike.y + layout.spike.h / 2) * TILE_SIZE,
        layout.spike.w * TILE_SIZE,
        layout.spike.h * TILE_SIZE,
        COLOR_SPIKE,
      ),
    );
  }

  private drawCannon(col: number, row: number, dir: CardinalDir): void {
    const { x, y } = this.cellCenter(col, row);
    this.register(this.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_CANNON));
    const tlX = col * TILE_SIZE;
    const tlY = row * TILE_SIZE;
    const r = BARREL_RECTS[dir];
    this.register(
      this.add.rectangle(
        tlX + (r.x + r.w / 2) * TILE_SIZE,
        tlY + (r.y + r.h / 2) * TILE_SIZE,
        r.w * TILE_SIZE,
        r.h * TILE_SIZE,
        COLOR_CANNON_BARREL,
      ),
    );
  }

  private drawKeyWall(col: number, row: number, colorIdx: number): void {
    const { x, y } = this.cellCenter(col, row);
    this.register(
      this.add.rectangle(
        x,
        y,
        TILE_SIZE,
        TILE_SIZE,
        KEY_COLORS_DARK[colorIdx] ?? 0x444444,
      ),
    );
  }

  private drawKey(col: number, row: number, colorIdx: number): void {
    const { x, y } = this.cellCenter(col, row);
    this.register(
      this.add.circle(x, y, TILE_SIZE * 0.25, KEY_COLORS_LIGHT[colorIdx] ?? 0xffffff),
    );
  }

  private drawGear(g: GearData): void {
    const { x, y } = this.cellCenter(g.x, g.y);
    const r = (g.size * TILE_SIZE) / 2;
    this.register(this.add.circle(x, y, r, COLOR_GEAR));
    const spokes = this.add.graphics();
    spokes.lineStyle(3, COLOR_GEAR_SPOKE, 1);
    spokes.lineBetween(x - r * 0.9, y, x + r * 0.9, y);
    spokes.lineBetween(x, y - r * 0.9, x, y + r * 0.9);
    this.register(spokes);
    this.register(this.add.circle(x, y, r * 0.22, COLOR_GEAR_HUB));

    // Path overlay — dashed-ish line through home + waypoints, plus a
    // small dot at each waypoint cell. Editor-only visual; the runtime
    // renders the gear without these so the path stays "behind the scenes"
    // during play.
    if (g.waypoints.length > 0) {
      const path = this.add.graphics();
      path.lineStyle(2, COLOR_GEAR_HUB, 0.6);
      path.beginPath();
      path.moveTo(x, y);
      for (const wp of g.waypoints) {
        const c = this.cellCenter(wp.x, wp.y);
        path.lineTo(c.x, c.y);
      }
      if (g.closed) {
        path.lineTo(x, y);
      }
      path.strokePath();
      this.register(path);
      for (const wp of g.waypoints) {
        const c = this.cellCenter(wp.x, wp.y);
        this.register(this.add.circle(c.x, c.y, TILE_SIZE * 0.1, COLOR_GEAR_HUB));
      }
    }

    // Bright ring around the gear currently in path-edit mode so the
    // user sees which gear's waypoints they're appending to.
    if (this.gearEditState?.gear === g) {
      const ring = this.add.graphics();
      ring.lineStyle(3, 0x4ca6ff, 0.95);
      ring.strokeCircle(x, y, r + 5);
      this.register(ring);
    }
  }

  private drawPortal(col: number, row: number, colorIdx: number): void {
    const { x, y } = this.cellCenter(col, row);
    this.register(
      this.add.circle(x, y, TILE_SIZE * 0.45, KEY_COLORS_DARK[colorIdx] ?? 0x444444),
    );
    this.register(
      this.add.circle(x, y, TILE_SIZE * 0.30, KEY_COLORS_LIGHT[colorIdx] ?? 0xffffff),
    );
  }

  private drawTurret(col: number, row: number): void {
    const { x, y } = this.cellCenter(col, row);
    this.register(this.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_CANNON));
    // Static "rest" pose — barrel pointing right at rotation 0, matching
    // the initial state Turret.barrel has before the first track update.
    this.register(
      this.add.rectangle(
        x + TILE_SIZE * 0.30,
        y,
        TILE_SIZE * 0.60,
        TILE_SIZE * 0.20,
        COLOR_CANNON_BARREL,
      ),
    );
    this.register(this.add.circle(x, y, TILE_SIZE * 0.16, COLOR_TURRET_HUB));
  }

  // Editor preview of a laser cannon. Shows the base + a barrel pointing
  // in the configured initial direction + a faint dashed-style line that
  // hints at the beam path. We don't run the duty cycle or rotation in
  // the editor — the runtime handles that.
  private drawLaserCannon(col: number, row: number, dir: CardinalDir): void {
    const { x, y } = this.cellCenter(col, row);
    this.register(this.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_LASER_CANNON));
    const tlX = col * TILE_SIZE;
    const tlY = row * TILE_SIZE;
    const r = BARREL_RECTS[dir];
    this.register(
      this.add.rectangle(
        tlX + (r.x + r.w / 2) * TILE_SIZE,
        tlY + (r.y + r.h / 2) * TILE_SIZE,
        r.w * TILE_SIZE,
        r.h * TILE_SIZE,
        COLOR_LASER_CANNON_BARREL,
      ),
    );
    this.register(this.add.circle(x, y, TILE_SIZE * 0.16, COLOR_LASER_HUB));
    // Beam-direction hint — short red line projecting one tile out from
    // the cannon edge in `dir`. Faint so it doesn't clutter the editor.
    const offsetMap: Record<CardinalDir, { dx: number; dy: number }> = {
      up: { dx: 0, dy: -1 },
      down: { dx: 0, dy: 1 },
      left: { dx: -1, dy: 0 },
      right: { dx: 1, dy: 0 },
    };
    const o = offsetMap[dir];
    const hint = this.add.graphics();
    hint.lineStyle(2, COLOR_LASER_BEAM, 0.5);
    hint.lineBetween(
      x + o.dx * TILE_SIZE * 0.5,
      y + o.dy * TILE_SIZE * 0.5,
      x + o.dx * TILE_SIZE * 1.5,
      y + o.dy * TILE_SIZE * 1.5,
    );
    this.register(hint);
  }

  // Decorative multi-cell text overlay. Bounds rendered as a faint
  // outline so empty / short text is still visible and clickable in
  // the editor; runtime drops the outline. Word-wrapping uses the
  // cell-width minus a small inner padding so glyphs don't bleed
  // across the bounds edge.
  private drawTextLabel(tl: TextLabelData): void {
    const tlX = tl.x * TILE_SIZE;
    const tlY = tl.y * TILE_SIZE;
    const w = tl.width * TILE_SIZE;
    const h = tl.height * TILE_SIZE;
    const pad = 4;

    // Faint dashed-style bounds outline so an empty / short label is
    // still locatable + clickable in the editor.
    const outline = this.add.graphics();
    outline.lineStyle(1, 0x666c8c, 0.5);
    outline.strokeRect(tlX, tlY, w, h);
    this.register(outline);

    if (tl.text.length > 0) {
      const text = this.add.text(tlX + pad, tlY + pad, tl.text, {
        color: '#cccccc',
        fontSize: '16px',
        fontFamily: 'system-ui, -apple-system, sans-serif',
        wordWrap: { width: w - pad * 2 },
      });
      this.register(text);
    }
  }

  private drawTeleport(col: number, row: number, targetPage: number): void {
    const { x, y } = this.cellCenter(col, row);
    this.register(this.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_TELEPORT));
    this.register(
      this.add
        .text(x, y, `→${targetPage + 1}`, {
          color: '#ffffff',
          fontSize: '16px',
          fontStyle: 'bold',
        })
        .setOrigin(0.5),
    );
  }

  private drawSpawn(col: number, row: number): void {
    const { x, y } = this.cellCenter(col, row);
    // Hollow blue square + 'S' so the spawn is unmistakable in the editor.
    // (At runtime the spawn cell is empty — only the player visual sits there.)
    const r = this.add.rectangle(x, y, TILE_SIZE, TILE_SIZE);
    r.setStrokeStyle(3, COLOR_PLAYER);
    this.register(r);
    this.register(
      this.add
        .text(x, y, 'S', {
          color: '#4ca6ff',
          fontSize: '20px',
          fontStyle: 'bold',
        })
        .setOrigin(0.5),
    );
  }

  private drawExit(col: number, row: number): void {
    const { x, y } = this.cellCenter(col, row);
    this.register(this.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_EXIT));
    this.register(
      this.add
        .text(x, y, 'X', {
          color: '#ffffff',
          fontSize: '20px',
          fontStyle: 'bold',
        })
        .setOrigin(0.5),
    );
  }

  // --- DOM chrome --------------------------------------------------------

  private updateLabels(): void {
    if (this.pageLabel) {
      this.pageLabel.textContent =
        `${this.currentPageIndex + 1} / ${this.level.pages.length}`;
    }
    if (this.fileLabel) {
      this.fileLabel.textContent = this.level.name;
    }
  }

  private changePage(delta: number): void {
    const next = this.currentPageIndex + delta;
    if (next < 0 || next >= this.level.pages.length) return;
    this.currentPageIndex = next;
    // gearEditState + selectedElement reference data on the *previous*
    // page; the user implicitly ends both sub-states by leaving.
    this.gearEditState = null;
    this.selectedElement = null;
    this.cancelDrag();
    this.renderPage();
    this.renderParamsPanel();
    this.updateLabels();
  }

  // Save back to disk via the Vite dev-server middleware. The endpoint
  // whitelists levels/level-NN.json, so saving from a "no known path"
  // scene falls back to a download — keeps changes recoverable when
  // the editor is opened against an ad-hoc level (e.g. DEFAULT_LEVEL_URL).
  private async saveLevel(): Promise<void> {
    if (!this.levelPath) {
      this.downloadLevel();
      return;
    }
    const saveBtn = this.palette?.querySelector(
      '[data-action="save"]',
    ) as HTMLButtonElement | null;
    try {
      const response = await fetch('/api/save-level', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ path: this.levelPath, level: this.level }),
      });
      if (!response.ok) {
        const err = (await response.json().catch(() => ({}))) as { error?: string };
        alert(`Save failed: ${err.error ?? response.statusText}`);
        return;
      }
      this.flashSaveButton(saveBtn);
    } catch (err) {
      alert(
        `Save failed: ${(err as Error).message}\n\n` +
          `The save endpoint only exists when running 'npm run dev'.`,
      );
    }
  }

  private flashSaveButton(btn: HTMLButtonElement | null): void {
    if (!btn) return;
    const original = btn.textContent;
    btn.textContent = 'Saved!';
    btn.classList.add('palette-btn-saved');
    setTimeout(() => {
      btn.textContent = original;
      btn.classList.remove('palette-btn-saved');
    }, 900);
  }

  // Fallback when no levelPath is known — kicks the JSON down through
  // a browser download so the user can still recover their edits.
  private downloadLevel(): void {
    const blob = new Blob([JSON.stringify(this.level, null, 2)], {
      type: 'application/json',
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${this.level.name.replace(/\s+/g, '-').toLowerCase()}.json`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  }

  // --- tool palette ------------------------------------------------------

  private buildPalette(): void {
    if (this.palette) return;
    const palette = document.createElement('div');
    palette.className = 'editor-palette';
    // Right-edge sidebar holding everything: file chrome on top
    // (EDIT MODE label, page nav, Load / Save / Play), then a 2-column
    // grid of single-purpose tool buttons, then params for the active
    // tool. The top toolbar that previously sat above the canvas was
    // folded in here so the canvas's top rows aren't hidden anymore.
    palette.innerHTML = `
      <div class="palette-section-label">EDIT MODE</div>
      <div class="palette-file-label" data-role="file-label"></div>
      <div class="palette-page-nav">
        <button data-action="prev-page" class="palette-btn palette-stepper-btn">◀</button>
        <span class="palette-stepper-value" data-role="page-label"></span>
        <button data-action="next-page" class="palette-btn palette-stepper-btn">▶</button>
      </div>
      <div class="palette-actions">
        <button data-action="add-page" class="palette-btn">+ Page</button>
        <button data-action="del-page" class="palette-btn">− Page</button>
      </div>
      <div class="palette-actions">
        <button data-action="menu" class="palette-btn">Menu</button>
        <button data-action="save" class="palette-btn">Save</button>
      </div>
      <button data-action="play" class="palette-btn palette-btn-primary palette-btn-full">▶ Play</button>
      <div class="palette-divider"></div>
      <button data-tool="select" class="palette-btn palette-btn-full">Select / Move</button>
      <div class="palette-tools">
        <button data-tool="wall" class="palette-btn">Wall</button>
        <button data-tool="coin" class="palette-btn">Coin</button>
        <button data-tool="glass" class="palette-btn">Glass</button>
        <button data-tool="spike_block" class="palette-btn">SBlock</button>
        <button data-tool="spike" class="palette-btn">Spike</button>
        <button data-tool="conveyor" class="palette-btn">Conveyor</button>
        <button data-tool="cannon" class="palette-btn">Cannon</button>
        <button data-tool="turret" class="palette-btn">Turret</button>
        <button data-tool="laser_cannon" class="palette-btn">Laser</button>
        <button data-tool="gear" class="palette-btn">Gear</button>
        <button data-tool="portal" class="palette-btn">Portal</button>
        <button data-tool="key" class="palette-btn">Key</button>
        <button data-tool="key_wall" class="palette-btn">K-Wall</button>
        <button data-tool="teleport" class="palette-btn">Tele</button>
        <button data-tool="text" class="palette-btn">Text</button>
        <button data-tool="spawn" class="palette-btn">Spawn</button>
        <button data-tool="exit" class="palette-btn">Exit</button>
      </div>
      <button data-tool="eraser" class="palette-btn palette-btn-eraser palette-btn-full">Erase</button>
      <div class="palette-params" data-role="params"></div>
    `;
    document.body.appendChild(palette);
    this.palette = palette;
    this.paramsPanel = palette.querySelector('[data-role="params"]') as HTMLDivElement;
    this.pageLabel = palette.querySelector('[data-role="page-label"]');
    this.fileLabel = palette.querySelector('[data-role="file-label"]');
    this.updateLabels();
    palette.addEventListener('click', (ev) => this.onPaletteClick(ev));
    // Event-delegated input listener for the per-instance text-label
    // textarea. We can't re-render the params panel on each keystroke
    // (that destroys the textarea and steals focus mid-typing), so
    // text content updates flow through here directly into the level
    // data + a renderPage call.
    palette.addEventListener('input', (ev) => this.onPaletteInput(ev));
  }

  private destroyPalette(): void {
    if (this.palette) {
      this.palette.remove();
      this.palette = null;
      this.paramsPanel = null;
      this.pageLabel = null;
      this.fileLabel = null;
      this.selectedTool = null;
    }
  }

  // Click router for everything inside the palette. Branches on which
  // data-* attribute the clicked element carries:
  //   data-action     → file/page chrome (prev/next page, load, save, play)
  //   data-tool       → select that tool, re-render params panel
  //   data-param-dir  → set direction param for the active tool
  //   data-param-color→ set color param for the active tool
  //   data-param-step → step the active tool's numeric param by ±1
  private onPaletteClick(ev: MouseEvent): void {
    const target = ev.target as HTMLElement;

    const action = target.getAttribute('data-action');
    if (action) {
      this.handlePaletteAction(action);
      return;
    }

    const tool = target.getAttribute('data-tool');
    if (tool) {
      this.selectedTool = tool as ToolId;
      // Switching tools always ends a gear-path edit session and
      // clears the instance selection — both are sub-states of the
      // Select tool. closed flag is left as-is; the user explicitly
      // opens or closes via the gear-finish-open button or click-home.
      const hadSubState = this.gearEditState != null || this.selectedElement != null;
      this.gearEditState = null;
      this.selectedElement = null;
      if (hadSubState) this.renderPage();
      this.updateToolHighlight();
      this.renderParamsPanel();
      return;
    }
    if (!this.selectedTool) return;

    const dir = target.getAttribute('data-param-dir');
    if (dir) {
      if (this.selectedTool === 'spike' || this.selectedTool === 'cannon') {
        this.toolParams[this.selectedTool] = dir as CardinalDir;
      } else if (this.selectedTool === 'conveyor') {
        this.toolParams.conveyor = dir as ConveyorDir;
      }
      this.renderParamsPanel();
      return;
    }

    const color = target.getAttribute('data-param-color');
    if (color !== null) {
      if (
        this.selectedTool === 'portal' ||
        this.selectedTool === 'key' ||
        this.selectedTool === 'key_wall'
      ) {
        this.toolParams[this.selectedTool] = parseInt(color, 10);
      }
      this.renderParamsPanel();
      return;
    }

    const step = target.getAttribute('data-param-step');
    if (step && this.selectedTool === 'teleport') {
      const max = this.level.pages.length - 1;
      const next = this.toolParams.teleport + parseInt(step, 10);
      this.toolParams.teleport = Math.max(0, Math.min(next, max));
      this.renderParamsPanel();
      return;
    }

    // ---- Instance editing (Select tool with selectedElement) ----
    // Routes click attributes prefixed `data-elem-*` straight into the
    // selected element's ref. Each handler narrows the SelectedElement
    // discriminated union before mutating, so unrelated kinds silently
    // ignore inapplicable inputs.
    if (this.selectedElement) {
      const elemDir = target.getAttribute('data-elem-dir');
      if (elemDir) {
        const sel = this.selectedElement;
        if (sel.kind === 'spike' || sel.kind === 'cannon' || sel.kind === 'laser_cannon') {
          sel.ref.dir = elemDir as CardinalDir;
        }
        this.renderPage();
        this.renderParamsPanel();
        return;
      }
      const convDir = target.getAttribute('data-elem-conveyor-dir');
      if (convDir) {
        if (this.selectedElement.kind === 'conveyor') {
          this.selectedElement.ref.dir = convDir as ConveyorDir;
        }
        this.renderPage();
        this.renderParamsPanel();
        return;
      }
      const elemColor = target.getAttribute('data-elem-color');
      if (elemColor !== null) {
        const sel = this.selectedElement;
        if (sel.kind === 'key' || sel.kind === 'key_wall') {
          sel.ref.color = parseInt(elemColor, 10);
        }
        this.renderPage();
        this.renderParamsPanel();
        return;
      }
      const lasRot = target.getAttribute('data-elem-laser-rotate');
      if (lasRot) {
        if (this.selectedElement.kind === 'laser_cannon') {
          this.selectedElement.ref.rotate = lasRot as LaserRotateMode;
        }
        this.renderParamsPanel();
        return;
      }
      const toggle = target.getAttribute('data-elem-toggle');
      if (toggle === 'closed' && this.selectedElement.kind === 'gear') {
        this.selectedElement.ref.closed = !this.selectedElement.ref.closed;
        this.renderPage();
        this.renderParamsPanel();
        return;
      }
      const elemProp = target.getAttribute('data-elem-prop');
      const elemStep = target.getAttribute('data-elem-step');
      if (elemProp && elemStep) {
        this.adjustElementProp(this.selectedElement, elemProp, parseInt(elemStep, 10));
        return;
      }
    }

    // Laser cannon params — direction (4 cardinals), rotate mode (none /
    // cw / ccw), and the duration / downtime steppers (0.5-second
    // increments; duration clamped at 0 = "continuous", downtime
    // clamped at 0.5 minimum).
    if (this.selectedTool === 'laser_cannon') {
      const lcDir = target.getAttribute('data-param-laser-dir');
      if (lcDir) {
        this.toolParams.laser_cannon.dir = lcDir as CardinalDir;
        this.renderParamsPanel();
        return;
      }
      const lcRot = target.getAttribute('data-param-laser-rotate');
      if (lcRot) {
        this.toolParams.laser_cannon.rotate = lcRot as LaserRotateMode;
        this.renderParamsPanel();
        return;
      }
      const lcDur = target.getAttribute('data-param-laser-dur');
      if (lcDur) {
        const delta = parseInt(lcDur, 10) * 0.5;
        const next = this.toolParams.laser_cannon.duration + delta;
        // Clamp at 0 (continuous) and a generous upper bound.
        this.toolParams.laser_cannon.duration = Math.max(0, Math.min(next, 30));
        this.renderParamsPanel();
        return;
      }
      const lcDown = target.getAttribute('data-param-laser-down');
      if (lcDown) {
        const delta = parseInt(lcDown, 10) * 0.5;
        const next = this.toolParams.laser_cannon.downtime + delta;
        // Min 0.5 — a 0-downtime non-continuous cycle would mean off-
        // for-zero, which is effectively continuous; the user has the
        // duration=0 path for that explicitly.
        this.toolParams.laser_cannon.downtime = Math.max(0.5, Math.min(next, 30));
        this.renderParamsPanel();
        return;
      }
    }

    // Text tool sticky params: width and height steppers (text content
    // is intentionally edited per-instance, not at placement time).
    // Min 1 cell each; we don't clamp the upper end here because the
    // page may be wider/taller than 30 — placement-time bounds check
    // (isAreaClearForText) catches out-of-page sizes.
    if (this.selectedTool === 'text') {
      const tw = target.getAttribute('data-param-text-w');
      if (tw) {
        const next = this.toolParams.text.width + parseInt(tw, 10);
        this.toolParams.text.width = Math.max(1, next);
        this.renderParamsPanel();
        return;
      }
      const th = target.getAttribute('data-param-text-h');
      if (th) {
        const next = this.toolParams.text.height + parseInt(th, 10);
        this.toolParams.text.height = Math.max(1, next);
        this.renderParamsPanel();
        return;
      }
    }
  }

  // Captures keystroke-by-keystroke updates to the per-instance text
  // textarea, written through to the selected element's `text` field
  // and reflected on the canvas. Crucially does NOT re-render the
  // params panel — that would destroy the textarea mid-typing.
  private onPaletteInput(ev: Event): void {
    const target = ev.target as HTMLElement;
    if (target.getAttribute('data-elem-text-input') === null) return;
    if (this.selectedElement?.kind !== 'text_label') return;
    this.selectedElement.ref.text = (target as HTMLTextAreaElement).value;
    this.renderPage();
  }

  private handlePaletteAction(action: string): void {
    switch (action) {
      case 'prev-page':
        this.changePage(-1);
        return;
      case 'next-page':
        this.changePage(1);
        return;
      case 'save':
        // Fire-and-forget — saveLevel() handles its own UI feedback.
        void this.saveLevel();
        return;
      case 'menu':
        this.scene.start('MenuScene');
        return;
      case 'play':
        this.scene.start('PlayScene', {
          level: this.level,
          pageIndex: this.currentPageIndex,
          fromEditor: true,
          levelPath: this.levelPath,
        });
        return;
      case 'gear-finish-open':
        // Explicit "leave open" finalize — overrides any prior closed
        // flag so the user can re-open a previously-closed gear.
        if (this.gearEditState) {
          this.gearEditState.gear.closed = false;
          this.gearEditState = null;
        }
        this.renderPage();
        this.renderParamsPanel();
        return;
      case 'add-page':
        this.addPage();
        return;
      case 'del-page':
        this.deletePage();
        return;
    }
  }

  // Adds a blank page after the current page and switches to it. Tile
  // dimensions match the current page so cross-page navigation looks
  // consistent (the runtime doesn't formally require uniform sizes,
  // but mixing them would surprise authors). Spawn defaults to (1,1) —
  // the user will reposition with the spawn tool once walls are in.
  private addPage(): void {
    const current = this.level.pages[this.currentPageIndex];
    if (!current) return;
    const cols = current.tiles[0]!.length;
    const rows = current.tiles.length;
    const blank = '.'.repeat(cols);
    const newPage: PageData = {
      tiles: Array.from({ length: rows }, () => blank),
      spawn: { x: 1, y: 1 },
    };
    this.level.pages.splice(this.currentPageIndex + 1, 0, newPage);
    // Bump exit page index if the inserted page sits before the exit's
    // page. Teleports holding a target_page that points past the
    // insertion point also need a +1 nudge so they keep aiming at the
    // same logical page.
    if (this.level.exit.page > this.currentPageIndex) {
      this.level.exit.page += 1;
    }
    for (const pg of this.level.pages) {
      if (!pg.teleports) continue;
      for (const t of pg.teleports) {
        if (t.target_page > this.currentPageIndex) t.target_page += 1;
      }
    }
    this.currentPageIndex += 1;
    this.gearEditState = null;
    this.selectedElement = null;
    this.cancelDrag();
    this.renderPage();
    this.renderParamsPanel();
    this.updateLabels();
  }

  // Removes the current page after a confirm. Refuses when only one
  // page remains (a level needs at least one). Updates the exit and
  // any teleport target_page values:
  //   - exit on the deleted page  → reassigned to page 0
  //   - exit after the deleted page → index shifts -1
  //   - teleport target equals the deleted page → that teleport is
  //     dropped (the destination no longer exists)
  //   - teleport target after the deleted page → target shifts -1
  private deletePage(): void {
    if (this.level.pages.length <= 1) {
      window.alert('Cannot delete the last remaining page.');
      return;
    }
    const idx = this.currentPageIndex;
    const ok = window.confirm(
      `Delete page ${idx + 1}? This cannot be undone.`,
    );
    if (!ok) return;

    this.level.pages.splice(idx, 1);

    if (this.level.exit.page === idx) {
      this.level.exit.page = 0;
    } else if (this.level.exit.page > idx) {
      this.level.exit.page -= 1;
    }
    // Clamp exit (x, y) into its page's grid — defensive against
    // non-uniform page sizes in legacy levels. New pages added via
    // addPage match the current page's dims, so this is mostly a no-op.
    const exitPage = this.level.pages[this.level.exit.page];
    if (exitPage) {
      const cols = exitPage.tiles[0]!.length;
      const rows = exitPage.tiles.length;
      this.level.exit.x = Math.min(Math.max(0, this.level.exit.x), cols - 1);
      this.level.exit.y = Math.min(Math.max(0, this.level.exit.y), rows - 1);
    }

    for (const pg of this.level.pages) {
      if (!pg.teleports) continue;
      pg.teleports = pg.teleports.filter((t) => {
        if (t.target_page === idx) return false;
        if (t.target_page > idx) t.target_page -= 1;
        return true;
      });
    }

    if (this.currentPageIndex >= this.level.pages.length) {
      this.currentPageIndex = this.level.pages.length - 1;
    }
    this.gearEditState = null;
    this.selectedElement = null;
    this.cancelDrag();
    this.renderPage();
    this.renderParamsPanel();
    this.updateLabels();
  }

  private updateToolHighlight(): void {
    if (!this.palette) return;
    this.palette.querySelectorAll('[data-tool]').forEach((b) => {
      b.classList.toggle('selected', b.getAttribute('data-tool') === this.selectedTool);
    });
  }

  // --- params panel ------------------------------------------------------

  // Re-renders the params region below the tool grid for whichever tool
  // is currently selected. Empty for tools without editable params.
  private renderParamsPanel(): void {
    if (!this.paramsPanel) return;
    if (!this.selectedTool) {
      this.paramsPanel.innerHTML = '';
      return;
    }
    switch (this.selectedTool) {
      case 'spike':
      case 'cannon':
        this.paramsPanel.innerHTML = this.dirParamHtml(
          this.toolParams[this.selectedTool],
          ['up', 'down', 'left', 'right'],
        );
        return;
      case 'conveyor':
        this.paramsPanel.innerHTML = this.dirParamHtml(this.toolParams.conveyor, ['cw', 'ccw']);
        return;
      case 'portal':
      case 'key':
      case 'key_wall':
        this.paramsPanel.innerHTML = this.colorParamHtml(this.toolParams[this.selectedTool]);
        return;
      case 'teleport':
        this.paramsPanel.innerHTML = this.teleportParamHtml();
        return;
      case 'select':
        this.paramsPanel.innerHTML = this.selectParamHtml();
        return;
      case 'laser_cannon':
        this.paramsPanel.innerHTML = this.laserCannonParamHtml();
        return;
      case 'text':
        this.paramsPanel.innerHTML = this.textToolParamHtml();
        return;
      default:
        this.paramsPanel.innerHTML = '';
    }
  }

  // Tool-sticky params for the Text tool: width + height of the
  // bounds. Text content is left at the placement default ("Text") so
  // the user can immediately see and click the new label; the actual
  // copy is edited per-instance via Select.
  private textToolParamHtml(): string {
    const tp = this.toolParams.text;
    return `
      <div class="palette-section-label">WIDTH</div>
      <div class="palette-stepper">
        <button data-param-text-w="-1" class="palette-btn palette-stepper-btn">−</button>
        <span class="palette-stepper-value">${tp.width} cells</span>
        <button data-param-text-w="1" class="palette-btn palette-stepper-btn">+</button>
      </div>
      <div class="palette-section-label">HEIGHT</div>
      <div class="palette-stepper">
        <button data-param-text-h="-1" class="palette-btn palette-stepper-btn">−</button>
        <span class="palette-stepper-value">${tp.height} cells</span>
        <button data-param-text-h="1" class="palette-btn palette-stepper-btn">+</button>
      </div>
    `;
  }

  // Laser cannon params: initial direction (4 cardinals) + rotate mode
  // (None / CW / CCW) + duration & downtime steppers (0.5-second
  // increments). duration === 0 means continuous fire — the downtime
  // stepper is shown grayed out but still editable so it doesn't
  // disappear from layout when the user toggles back to a finite
  // duration.
  private laserCannonParamHtml(): string {
    const lc = this.toolParams.laser_cannon;
    const dirLabels: Record<CardinalDir, string> = {
      up: '↑', down: '↓', left: '←', right: '→',
    };
    const dirButtons = (['up', 'down', 'left', 'right'] as CardinalDir[])
      .map((d) => {
        const sel = d === lc.dir ? ' selected' : '';
        return `<button data-param-laser-dir="${d}" class="palette-btn${sel}">${dirLabels[d]}</button>`;
      })
      .join('');
    const rotLabels: Record<LaserRotateMode, string> = {
      none: 'None', cw: 'CW', ccw: 'CCW',
    };
    const rotButtons = (['none', 'cw', 'ccw'] as LaserRotateMode[])
      .map((m) => {
        const sel = m === lc.rotate ? ' selected' : '';
        return `<button data-param-laser-rotate="${m}" class="palette-btn${sel}">${rotLabels[m]}</button>`;
      })
      .join('');
    const durLabel = lc.duration === 0 ? 'continuous' : `${lc.duration.toFixed(1)} s`;
    const downLabel = `${lc.downtime.toFixed(1)} s`;
    return `
      <div class="palette-section-label">DIRECTION</div>
      <div class="palette-grid-2">${dirButtons}</div>
      <div class="palette-section-label">ROTATE</div>
      <div class="palette-grid-2">${rotButtons}</div>
      <div class="palette-section-label">DURATION</div>
      <div class="palette-stepper">
        <button data-param-laser-dur="-1" class="palette-btn palette-stepper-btn">−</button>
        <span class="palette-stepper-value">${durLabel}</span>
        <button data-param-laser-dur="1" class="palette-btn palette-stepper-btn">+</button>
      </div>
      <div class="palette-section-label">DOWNTIME</div>
      <div class="palette-stepper">
        <button data-param-laser-down="-1" class="palette-btn palette-stepper-btn">−</button>
        <span class="palette-stepper-value">${downLabel}</span>
        <button data-param-laser-down="1" class="palette-btn palette-stepper-btn">+</button>
      </div>
    `;
  }

  // Select tool params: per-element editing when something is
  // selected; empty otherwise (Select with nothing chosen does nothing
  // until the user clicks an element on the map).
  private selectParamHtml(): string {
    if (this.selectedElement) {
      return this.elementParamHtml(this.selectedElement);
    }
    return '';
  }

  // Per-instance params for whichever element kind is selected.
  // Each returns its own header label + control set; the gear case
  // also embeds the path-edit hint when a session is open.
  private elementParamHtml(sel: SelectedElement): string {
    switch (sel.kind) {
      case 'glass_wall':
        return this.elemHeader('Glass Wall')
          + this.elemStepperHtml('Delay', sel.ref.delay.toFixed(1) + ' s', 'delay');
      case 'spike_block': {
        const dur = sel.ref.duration ?? 0;
        const down = sel.ref.downtime ?? 3.0;
        const durLabel = dur === 0 ? 'always extended' : `${dur.toFixed(1)} s`;
        return this.elemHeader('Spike Block')
          + this.elemStepperHtml('Extend', durLabel, 'duration')
          + this.elemStepperHtml('Retract', `${down.toFixed(1)} s`, 'downtime');
      }
      case 'spike': {
        const dur = sel.ref.duration ?? 0;
        const down = sel.ref.downtime ?? 3.0;
        const durLabel = dur === 0 ? 'always extended' : `${dur.toFixed(1)} s`;
        return this.elemHeader('Spike')
          + this.elemDirHtml(sel.ref.dir)
          + this.elemStepperHtml('Extend', durLabel, 'duration')
          + this.elemStepperHtml('Retract', `${down.toFixed(1)} s`, 'downtime');
      }
      case 'conveyor':
        return this.elemHeader('Conveyor')
          + this.elemConveyorDirHtml(sel.ref.dir);
      case 'cannon':
        return this.elemHeader('Cannon')
          + this.elemDirHtml(sel.ref.dir)
          + this.elemStepperHtml('Period', sel.ref.period.toFixed(1) + ' s', 'period')
          + this.elemStepperHtml('Bullet speed', sel.ref.bullet_speed.toFixed(1) + ' t/s', 'bullet_speed');
      case 'turret':
        return this.elemHeader('Turret')
          + this.elemStepperHtml('Period', sel.ref.period.toFixed(1) + ' s', 'period')
          + this.elemStepperHtml('Bullet speed', sel.ref.bullet_speed.toFixed(1) + ' t/s', 'bullet_speed');
      case 'gear': {
        const editing = this.gearEditState?.gear === sel.ref;
        const closedLabel = sel.ref.closed ? 'Closed loop' : 'Open path';
        const pathBlock = editing
          ? `<div class="palette-section-label">EDIT GEAR PATH</div>
             <div class="palette-hint">
               Click empty cells to add waypoints.<br>
               Click another gear to switch edit target.<br>
               Click this gear's center to close the loop.
             </div>
             <button data-action="gear-finish-open" class="palette-btn palette-btn-full">Done (open)</button>`
          : '';
        return this.elemHeader('Gear')
          + this.elemStepperHtml('Size', `${sel.ref.size} t`, 'size')
          + this.elemStepperHtml('Speed', sel.ref.speed.toFixed(1) + ' t/s', 'speed')
          + this.elemStepperHtml('Spin', sel.ref.spin.toFixed(1) + ' r/s', 'spin')
          + `<button data-elem-toggle="closed" class="palette-btn palette-btn-full">${closedLabel}</button>`
          + pathBlock;
      }
      case 'key':
        return this.elemHeader('Key')
          + this.elemColorHtml(sel.ref.color);
      case 'key_wall':
        return this.elemHeader('Key Wall')
          + this.elemColorHtml(sel.ref.color);
      case 'teleport': {
        const max = this.level.pages.length - 1;
        const v = Math.max(0, Math.min(sel.ref.target_page, max));
        return this.elemHeader('Teleport')
          + this.elemStepperHtml('Target page', `${v + 1} / ${max + 1}`, 'target_page');
      }
      case 'laser_cannon': {
        const lc = sel.ref;
        const durLabel = lc.duration === 0 ? 'continuous' : `${lc.duration.toFixed(1)} s`;
        return this.elemHeader('Laser Cannon')
          + this.elemDirHtml(lc.dir)
          + this.elemLaserRotateHtml(lc.rotate)
          + this.elemStepperHtml('Duration', durLabel, 'duration')
          + this.elemStepperHtml('Downtime', lc.downtime.toFixed(1) + ' s', 'downtime');
      }
      case 'text_label': {
        // The textarea uses an `input` event listener on the palette
        // (event-delegated) rather than re-rendering on each keystroke,
        // so typing here doesn't blow away its own focus / selection.
        // Width / height steppers DO re-render the panel — clicking
        // them implies the user is done typing for the moment, which
        // matches the loss of focus the re-render incurs.
        const ref = sel.ref;
        // Escape HTML special chars in textarea body (preserves
        // newlines naturally — the textarea handles \n).
        const safeText = ref.text
          .replace(/&/g, '&amp;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;');
        return this.elemHeader('Text')
          + this.elemStepperHtml('Width', `${ref.width} cells`, 'width')
          + this.elemStepperHtml('Height', `${ref.height} cells`, 'height')
          + `<div class="palette-section-label">CONTENT</div>
             <textarea data-elem-text-input class="palette-textarea" rows="5">${safeText}</textarea>`;
      }
    }
  }

  private elemHeader(name: string): string {
    return `<div class="palette-section-label">${name.toUpperCase()}</div>`;
  }

  // Direction picker for instance editing. Same 4-cardinal layout as
  // the tool-side dirParamHtml but writes via data-elem-dir so the
  // click router knows it targets the selected element.
  private elemDirHtml(current: CardinalDir): string {
    const labels: Record<CardinalDir, string> = { up: '↑', down: '↓', left: '←', right: '→' };
    const buttons = (['up', 'down', 'left', 'right'] as CardinalDir[])
      .map((d) => {
        const sel = d === current ? ' selected' : '';
        return `<button data-elem-dir="${d}" class="palette-btn${sel}">${labels[d]}</button>`;
      })
      .join('');
    return `
      <div class="palette-section-label">DIRECTION</div>
      <div class="palette-grid-2">${buttons}</div>
    `;
  }

  private elemConveyorDirHtml(current: ConveyorDir): string {
    const labels: Record<ConveyorDir, string> = { cw: 'CW →', ccw: 'CCW ←' };
    const buttons = (['cw', 'ccw'] as ConveyorDir[])
      .map((d) => {
        const sel = d === current ? ' selected' : '';
        return `<button data-elem-conveyor-dir="${d}" class="palette-btn${sel}">${labels[d]}</button>`;
      })
      .join('');
    return `
      <div class="palette-section-label">DIRECTION</div>
      <div class="palette-grid-2">${buttons}</div>
    `;
  }

  private elemColorHtml(current: number): string {
    const buttons = KEY_COLORS_LIGHT.map((color, i) => {
      const hex = '#' + color.toString(16).padStart(6, '0');
      const sel = i === current ? ' selected' : '';
      return `<button data-elem-color="${i}" class="palette-btn palette-color${sel}" style="background:${hex}"></button>`;
    }).join('');
    return `
      <div class="palette-section-label">COLOR</div>
      <div class="palette-color-row">${buttons}</div>
    `;
  }

  private elemLaserRotateHtml(current: LaserRotateMode): string {
    const labels: Record<LaserRotateMode, string> = { none: 'None', cw: 'CW', ccw: 'CCW' };
    const buttons = (['none', 'cw', 'ccw'] as LaserRotateMode[])
      .map((m) => {
        const sel = m === current ? ' selected' : '';
        return `<button data-elem-laser-rotate="${m}" class="palette-btn${sel}">${labels[m]}</button>`;
      })
      .join('');
    return `
      <div class="palette-section-label">ROTATE</div>
      <div class="palette-grid-2">${buttons}</div>
    `;
  }

  // Step a numeric property on the selected element by ±1 increment.
  // Each (kind, prop) pair has its own per-step amount and clamp.
  // Re-renders the page (some props affect visuals — gear size,
  // cannon dir) and the params panel (so the displayed value updates).
  private adjustElementProp(sel: SelectedElement, prop: string, dir: number): void {
    const clamp = (v: number, min: number, max: number) =>
      Math.max(min, Math.min(v, max));

    if (sel.kind === 'glass_wall' && prop === 'delay') {
      sel.ref.delay = clamp(sel.ref.delay + dir * 0.5, 0, 30);
    } else if (sel.kind === 'spike' || sel.kind === 'spike_block') {
      // duration: 0 → continuous; otherwise stepped 0.5s up to 30.
      // downtime: min 0.5s so a non-continuous cycle has a real off
      // phase (mirrors the laser's downtime clamp).
      if (prop === 'duration') {
        const cur = sel.ref.duration ?? 0;
        sel.ref.duration = clamp(cur + dir * 0.5, 0, 30);
      } else if (prop === 'downtime') {
        const cur = sel.ref.downtime ?? 3.0;
        sel.ref.downtime = clamp(cur + dir * 0.5, 0.5, 30);
      }
    } else if (sel.kind === 'cannon') {
      if (prop === 'period') sel.ref.period = clamp(sel.ref.period + dir * 0.5, 0.5, 30);
      else if (prop === 'bullet_speed') sel.ref.bullet_speed = clamp(sel.ref.bullet_speed + dir * 0.5, 1, 30);
    } else if (sel.kind === 'turret') {
      if (prop === 'period') sel.ref.period = clamp(sel.ref.period + dir * 0.5, 0.5, 30);
      else if (prop === 'bullet_speed') sel.ref.bullet_speed = clamp(sel.ref.bullet_speed + dir * 0.5, 1, 30);
    } else if (sel.kind === 'gear') {
      if (prop === 'size') sel.ref.size = clamp(sel.ref.size + dir, 1, 4);
      else if (prop === 'speed') sel.ref.speed = clamp(sel.ref.speed + dir * 0.5, 0, 20);
      else if (prop === 'spin') sel.ref.spin = clamp(sel.ref.spin + dir * 0.5, 0, 20);
    } else if (sel.kind === 'teleport' && prop === 'target_page') {
      const max = this.level.pages.length - 1;
      sel.ref.target_page = clamp(sel.ref.target_page + dir, 0, max);
    } else if (sel.kind === 'laser_cannon') {
      if (prop === 'duration') sel.ref.duration = clamp(sel.ref.duration + dir * 0.5, 0, 30);
      else if (prop === 'downtime') sel.ref.downtime = clamp(sel.ref.downtime + dir * 0.5, 0.5, 30);
    } else if (sel.kind === 'text_label') {
      // Width / height step by 1 cell; clamp at 1 minimum and the
      // current page's grid dimensions so the text never extends
      // past the level edge.
      const page = this.level.pages[this.currentPageIndex];
      const cols = page?.tiles[0]?.length ?? 1;
      const rows = page?.tiles.length ?? 1;
      if (prop === 'width') {
        sel.ref.width = clamp(sel.ref.width + dir, 1, cols - sel.ref.x);
      } else if (prop === 'height') {
        sel.ref.height = clamp(sel.ref.height + dir, 1, rows - sel.ref.y);
      }
    }

    this.renderPage();
    this.renderParamsPanel();
  }

  private elemStepperHtml(label: string, valueText: string, propName: string): string {
    return `
      <div class="palette-section-label">${label.toUpperCase()}</div>
      <div class="palette-stepper">
        <button data-elem-prop="${propName}" data-elem-step="-1" class="palette-btn palette-stepper-btn">−</button>
        <span class="palette-stepper-value">${valueText}</span>
        <button data-elem-prop="${propName}" data-elem-step="1" class="palette-btn palette-stepper-btn">+</button>
      </div>
    `;
  }

  private dirParamHtml(current: string, dirs: string[]): string {
    const labels: Record<string, string> = {
      up: '↑', down: '↓', left: '←', right: '→',
      cw: 'CW →', ccw: 'CCW ←',
    };
    const buttons = dirs
      .map((d) => {
        const sel = d === current ? ' selected' : '';
        return `<button data-param-dir="${d}" class="palette-btn${sel}">${labels[d]}</button>`;
      })
      .join('');
    const gridClass = dirs.length === 4 ? 'palette-grid-2' : 'palette-grid-2';
    return `
      <div class="palette-section-label">DIRECTION</div>
      <div class="${gridClass}">${buttons}</div>
    `;
  }

  private colorParamHtml(current: number): string {
    const buttons = KEY_COLORS_LIGHT.map((color, i) => {
      const hex = '#' + color.toString(16).padStart(6, '0');
      const sel = i === current ? ' selected' : '';
      return `<button data-param-color="${i}" class="palette-btn palette-color${sel}" style="background:${hex}"></button>`;
    }).join('');
    return `
      <div class="palette-section-label">COLOR</div>
      <div class="palette-color-row">${buttons}</div>
    `;
  }

  // Stepper for teleport's target_page. Bounded by the level's page count;
  // the raw param value persists across selection so the user doesn't have
  // to re-step it every time they pick the teleport tool.
  private teleportParamHtml(): string {
    const max = this.level.pages.length - 1;
    const value = Math.max(0, Math.min(this.toolParams.teleport, max));
    return `
      <div class="palette-section-label">TARGET PAGE</div>
      <div class="palette-stepper">
        <button data-param-step="-1" class="palette-btn palette-stepper-btn">−</button>
        <span class="palette-stepper-value">${value + 1} / ${max + 1}</span>
        <button data-param-step="1" class="palette-btn palette-stepper-btn">+</button>
      </div>
    `;
  }

  // --- pointer handlers --------------------------------------------------

  private onPointerDown(p: Phaser.Input.Pointer): void {
    if (!this.selectedTool) return;
    const cell = this.cellAtPointer(p);
    if (!cell) return;

    if (this.selectedTool === 'select') {
      // Open a gesture; click-vs-drag is decided in onPointerMove /
      // onPointerUp based on whether the pointer leaves the start cell.
      this.selectGesture = { start: cell, dragGhost: null };
      return;
    }

    this.applyTool(this.selectedTool, cell.col, cell.row);
    this.renderPage();

    if (DRAG_ENABLED_TOOLS.has(this.selectedTool)) {
      this.placementDragState = { lastCol: cell.col, lastRow: cell.row };
    }
  }

  private onPointerMove(p: Phaser.Input.Pointer): void {
    if (this.selectGesture) {
      this.updateSelectGesture(p);
      return;
    }
    if (!this.placementDragState || !this.selectedTool) return;
    const cell = this.cellAtPointer(p);
    if (!cell) return;
    if (
      cell.col === this.placementDragState.lastCol &&
      cell.row === this.placementDragState.lastRow
    ) return;
    // applyTool silently no-ops on occupied cells (issue #3), so a drag
    // streak naturally skips over existing elements without overwriting.
    this.applyTool(this.selectedTool, cell.col, cell.row);
    this.renderPage();
    this.placementDragState.lastCol = cell.col;
    this.placementDragState.lastRow = cell.row;
  }

  private onPointerUp(p: Phaser.Input.Pointer): void {
    if (this.selectGesture) {
      this.finishSelectGesture(p);
      return;
    }
    this.placementDragState = null;
  }

  // Translate a pointer event to a tile cell, returning null if the
  // pointer is outside the level grid.
  private cellAtPointer(
    p: Phaser.Input.Pointer,
  ): { col: number; row: number } | null {
    const col = Math.floor(p.worldX / TILE_SIZE);
    const row = Math.floor(p.worldY / TILE_SIZE);
    const page = this.level.pages[this.currentPageIndex];
    if (!page) return null;
    const cols = page.tiles[0]!.length;
    const rows = page.tiles.length;
    if (col < 0 || col >= cols || row < 0 || row >= rows) return null;
    return { col, row };
  }

  // --- Select-tool gesture (click vs drag) -------------------------------

  // Pointermove while a Select gesture is open. The first time the
  // pointer leaves the start cell, if the start cell holds something
  // movable we arm drag mode by creating the ghost. Drag works
  // regardless of gear-edit state — moving an element doesn't conflict
  // with waypoint-add (which only fires on a click + same cell).
  private updateSelectGesture(p: Phaser.Input.Pointer): void {
    if (!this.selectGesture) return;
    const col = Math.floor(p.worldX / TILE_SIZE);
    const row = Math.floor(p.worldY / TILE_SIZE);

    const onStartCell =
      col === this.selectGesture.start.col && row === this.selectGesture.start.row;

    if (!this.selectGesture.dragGhost && !onStartCell) {
      const page = this.level.pages[this.currentPageIndex];
      const startHasElement =
        page != null &&
        this.isOccupied(page, this.selectGesture.start.col, this.selectGesture.start.row);
      if (startHasElement) {
        const ghost = this.add.rectangle(
          (col + 0.5) * TILE_SIZE,
          (row + 0.5) * TILE_SIZE,
          TILE_SIZE,
          TILE_SIZE,
          0xffffff,
        );
        ghost.setAlpha(0.35);
        ghost.setStrokeStyle(2, 0xffffff, 0.85);
        ghost.setDepth(1000);
        this.selectGesture.dragGhost = ghost;
      }
    }

    if (this.selectGesture.dragGhost) {
      this.selectGesture.dragGhost.setPosition(
        (col + 0.5) * TILE_SIZE,
        (row + 0.5) * TILE_SIZE,
      );
    }
  }

  // Resolves the gesture on pointerup. If the ghost was armed, this
  // is a drag — move the element. Otherwise it's a click — but only
  // honored when the up cell matches the down cell, so a half-finished
  // drag (start had no element, pointer wandered) is a silent cancel
  // rather than a misfire.
  private finishSelectGesture(p: Phaser.Input.Pointer): void {
    if (!this.selectGesture) return;
    const target = this.cellAtPointer(p);
    const page = this.level.pages[this.currentPageIndex];

    if (this.selectGesture.dragGhost) {
      if (target && page) {
        const sameCell =
          target.col === this.selectGesture.start.col &&
          target.row === this.selectGesture.start.row;
        if (!sameCell) {
          // Multi-cell elements (text_label) need a bounds-check
          // against the new area, ignoring cells the text already
          // occupies. Single-cell elements just check the drop cell.
          const startElem = this.findElementAt(
            page,
            this.selectGesture.start.col,
            this.selectGesture.start.row,
          );
          let canMove = false;
          if (startElem?.kind === 'text_label') {
            const dCol = target.col - this.selectGesture.start.col;
            const dRow = target.row - this.selectGesture.start.row;
            canMove = this.isAreaClearForText(
              page,
              startElem.ref.x + dCol,
              startElem.ref.y + dRow,
              startElem.ref.width,
              startElem.ref.height,
              startElem.ref,
            );
          } else {
            canMove = !this.isOccupied(page, target.col, target.row);
          }
          if (canMove) {
            this.moveElementAt(
              page,
              this.selectGesture.start.col,
              this.selectGesture.start.row,
              target.col,
              target.row,
            );
          }
        }
      }
      this.selectGesture.dragGhost.destroy();
    } else if (
      target &&
      target.col === this.selectGesture.start.col &&
      target.row === this.selectGesture.start.row
    ) {
      this.handleSelectClick(target.col, target.row);
    }

    this.selectGesture = null;
    this.renderPage();
  }

  // Click router for Select-tool clicks (no drag). Two layers:
  //   1. If a gear-edit session is open, the click is interpreted as a
  //      waypoint operation (close on home, switch on another gear,
  //      push on empty, ignore on other occupied).
  //   2. Otherwise, the click selects an element under the cursor (or
  //      deselects on empty).
  // Selecting a gear ALSO opens its waypoint-edit session, so the two
  // states stay in sync for the gear case.
  private handleSelectClick(col: number, row: number): void {
    const page = this.level.pages[this.currentPageIndex];
    if (!page) return;

    if (this.gearEditState) {
      const gear = this.gearEditState.gear;

      if (gear.x === col && gear.y === row) {
        // Click on edited-gear's home → close loop + exit edit (selection stays).
        gear.closed = true;
        this.gearEditState = null;
        this.renderParamsPanel();
        return;
      }

      const otherGear = page.gears?.find((g) => g.x === col && g.y === row);
      if (otherGear) {
        // Switch waypoint target AND selection.
        this.gearEditState = { gear: otherGear };
        this.selectedElement = { kind: 'gear', ref: otherGear };
        this.renderParamsPanel();
        return;
      }

      // Click on a non-gear element while editing → switch selection,
      // exit gear-edit (selection-of-element takes priority over the
      // waypoint flow when the click target is editable).
      const otherElement = this.findElementAt(page, col, row);
      if (otherElement) {
        this.gearEditState = null;
        this.selectedElement = otherElement;
        this.renderParamsPanel();
        return;
      }

      // Empty cell while editing → add waypoint.
      if (this.isOccupied(page, col, row)) return;
      if (gear.waypoints.some((w) => w.x === col && w.y === row)) return;
      gear.waypoints.push({ x: col, y: row });
      return;
    }

    // No gear-edit session — try to select an element at this cell.
    const found = this.findElementAt(page, col, row);
    if (found) {
      this.selectedElement = found;
      // Selecting a gear also opens path-edit — preserves the prior
      // "click gear to edit waypoints" UX.
      if (found.kind === 'gear') {
        this.gearEditState = { gear: found.ref };
      }
      this.renderParamsPanel();
      return;
    }

    // Empty cell with no edit session: deselect.
    if (this.selectedElement) {
      this.selectedElement = null;
      this.renderParamsPanel();
    }
  }

  // Used by shutdown / destroy / page-change to clean up an in-progress
  // gesture without mutating the level data.
  private cancelDrag(): void {
    this.placementDragState = null;
    if (this.selectGesture) {
      this.selectGesture.dragGhost?.destroy();
      this.selectGesture = null;
    }
  }

  // Returns a SelectedElement wrapper around whatever per-page array
  // entry sits at (col, row), or null if none. Walls (W) and coins (C)
  // are tile chars with no editable params, so they aren't selectable.
  // Portals are also skipped — color is shared per pair, and both
  // points already drag-move individually.
  private findElementAt(page: PageData, col: number, row: number): SelectedElement | null {
    const at = (e: { x: number; y: number }) => e.x === col && e.y === row;
    let e;
    if ((e = page.glass_walls?.find(at))) return { kind: 'glass_wall', ref: e };
    if ((e = page.spike_blocks?.find(at))) return { kind: 'spike_block', ref: e };
    if ((e = page.spikes?.find(at))) return { kind: 'spike', ref: e };
    if ((e = page.conveyors?.find(at))) return { kind: 'conveyor', ref: e };
    if ((e = page.cannons?.find(at))) return { kind: 'cannon', ref: e };
    if ((e = page.turrets?.find(at))) return { kind: 'turret', ref: e };
    if ((e = page.gears?.find(at))) return { kind: 'gear', ref: e };
    if ((e = page.keys?.find(at))) return { kind: 'key', ref: e };
    if ((e = page.key_walls?.find(at))) return { kind: 'key_wall', ref: e };
    if ((e = page.teleports?.find(at))) return { kind: 'teleport', ref: e };
    if ((e = page.laser_cannons?.find(at))) return { kind: 'laser_cannon', ref: e };
    // Text labels are multi-cell — the click matches if (col, row) is
    // anywhere in their bounds rect, not just the top-left anchor.
    const tl = page.text_labels?.find(
      (t) => col >= t.x && col < t.x + t.width && row >= t.y && row < t.y + t.height,
    );
    if (tl) return { kind: 'text_label', ref: tl };
    return null;
  }

  // After any operation that may have removed elements (eraseAt, page
  // change), drop selectedElement if its ref is no longer present in
  // the current page's arrays.
  private validateSelectedElement(): void {
    if (!this.selectedElement) return;
    const page = this.level.pages[this.currentPageIndex];
    if (!page) {
      this.selectedElement = null;
      return;
    }
    const ref = this.selectedElement.ref;
    const present =
      page.glass_walls?.includes(ref as GlassWallData) ||
      page.spike_blocks?.includes(ref as SpikeBlockData) ||
      page.spikes?.includes(ref as SpikeData) ||
      page.conveyors?.includes(ref as ConveyorData) ||
      page.cannons?.includes(ref as CannonData) ||
      page.turrets?.includes(ref as TurretData) ||
      page.gears?.includes(ref as GearData) ||
      page.keys?.includes(ref as KeyData) ||
      page.key_walls?.includes(ref as KeyWallData) ||
      page.teleports?.includes(ref as TeleportData) ||
      page.laser_cannons?.includes(ref as LaserCannonData) ||
      page.text_labels?.includes(ref as TextLabelData);
    if (!present) {
      this.selectedElement = null;
    }
  }

  // True if this cell holds anything that would collide with a new
  // placement: a tile char (wall/coin), any per-page element, the spawn
  // marker, or this page's exit. Used both to reject placement (issue #3)
  // and to decide whether a Select-tool click has something to grab.
  private isOccupied(page: PageData, col: number, row: number): boolean {
    const ch = page.tiles[row]?.charAt(col);
    if (ch === 'W' || ch === 'C') return true;

    const at = (e: { x: number; y: number }) => e.x === col && e.y === row;
    if (page.glass_walls?.some(at)) return true;
    if (page.spike_blocks?.some(at)) return true;
    if (page.spikes?.some(at)) return true;
    if (page.conveyors?.some(at)) return true;
    if (page.cannons?.some(at)) return true;
    if (page.key_walls?.some(at)) return true;
    if (page.keys?.some(at)) return true;
    if (page.turrets?.some(at)) return true;
    if (page.laser_cannons?.some(at)) return true;
    if (page.teleports?.some(at)) return true;
    if (page.gears?.some(at)) return true;
    if (page.portals?.some((p) => p.points.some(at))) return true;
    // Text labels span multi-cell bounds; any cell inside counts.
    if (page.text_labels?.some(
      (t) => col >= t.x && col < t.x + t.width && row >= t.y && row < t.y + t.height,
    )) return true;

    if (page.spawn.x === col && page.spawn.y === row) return true;
    if (
      this.level.exit.page === this.currentPageIndex &&
      this.level.exit.x === col &&
      this.level.exit.y === row
    ) return true;

    return false;
  }

  // Move whatever's at (srcCol, srcRow) to (dstCol, dstRow). Caller is
  // responsible for ensuring the target is unoccupied. For wall/coin
  // tiles, swaps the char in the row strings; for everything else,
  // mutates the matching element's x/y in place. Gear waypoints and
  // unselected portal points stay where they are — only the clicked
  // entity moves.
  private moveElementAt(
    page: PageData,
    srcCol: number,
    srcRow: number,
    dstCol: number,
    dstRow: number,
  ): void {
    const at = (e: { x: number; y: number }) => e.x === srcCol && e.y === srcRow;
    const move = (e: { x: number; y: number }) => {
      e.x = dstCol;
      e.y = dstRow;
    };

    const r = page.tiles[srcRow]!;
    const ch = r.charAt(srcCol);
    if (ch === 'W' || ch === 'C') {
      page.tiles[srcRow] = r.slice(0, srcCol) + '.' + r.slice(srcCol + 1);
      const r2 = page.tiles[dstRow]!;
      page.tiles[dstRow] = r2.slice(0, dstCol) + ch + r2.slice(dstCol + 1);
      return;
    }

    page.glass_walls?.forEach((e) => { if (at(e)) move(e); });
    page.spike_blocks?.forEach((e) => { if (at(e)) move(e); });
    page.spikes?.forEach((e) => { if (at(e)) move(e); });
    page.conveyors?.forEach((e) => { if (at(e)) move(e); });
    page.cannons?.forEach((e) => { if (at(e)) move(e); });
    page.key_walls?.forEach((e) => { if (at(e)) move(e); });
    page.keys?.forEach((e) => { if (at(e)) move(e); });
    page.turrets?.forEach((e) => { if (at(e)) move(e); });
    page.laser_cannons?.forEach((e) => { if (at(e)) move(e); });
    page.teleports?.forEach((e) => { if (at(e)) move(e); });
    page.gears?.forEach((g) => { if (at(g)) move(g); });
    page.portals?.forEach((p) =>
      p.points.forEach((pt) => { if (at(pt)) move(pt); }),
    );
    // Text labels: multi-cell, so we shift by the (dst − src) delta
    // rather than teleporting the top-left to the cursor cell. The
    // click cell-vs-text-bounds test picks the right text when the
    // user grabs anywhere inside its area.
    const dCol = dstCol - srcCol;
    const dRow = dstRow - srcRow;
    page.text_labels?.forEach((t) => {
      if (
        srcCol >= t.x && srcCol < t.x + t.width &&
        srcRow >= t.y && srcRow < t.y + t.height
      ) {
        t.x += dCol;
        t.y += dRow;
      }
    });

    if (page.spawn.x === srcCol && page.spawn.y === srcRow) {
      move(page.spawn);
    }
    if (
      this.level.exit.page === this.currentPageIndex &&
      this.level.exit.x === srcCol &&
      this.level.exit.y === srcRow
    ) {
      this.level.exit.x = dstCol;
      this.level.exit.y = dstRow;
    }
  }

  // --- tool dispatch -----------------------------------------------------

  // Single placement entry point. Refuses to overwrite — issue #3 — so
  // any cell with an existing element rejects new placements (the user
  // must erase first). Eraser is its own branch. All directional /
  // colored / target-bearing tools read their settings from `toolParams`.
  private applyTool(tool: ToolId, col: number, row: number): void {
    const page = this.level.pages[this.currentPageIndex]!;

    if (tool === 'eraser') { this.eraseAt(page, col, row); return; }
    if (tool === 'select') return;  // select doesn't place; handled separately

    if (this.isOccupied(page, col, row)) return;

    if (tool === 'spawn')  { page.spawn = { x: col, y: row }; return; }
    if (tool === 'exit')   {
      this.level.exit = { page: this.currentPageIndex, x: col, y: row };
      return;
    }

    switch (tool) {
      case 'wall':
        this.setTile(page, col, row, 'W');
        return;
      case 'coin':
        this.setTile(page, col, row, 'C');
        return;
      case 'glass':
        this.appendTo(page, 'glass_walls', { x: col, y: row, delay: DEFAULT_GLASS_DELAY });
        return;
      case 'spike_block':
        // duration 0 = always extended (legacy behavior). User can
        // step it up via per-instance editing to enable the cycle.
        this.appendTo(page, 'spike_blocks', { x: col, y: row, duration: 0, downtime: 3.0 });
        return;
      case 'spike':
        this.appendTo(page, 'spikes', {
          x: col, y: row, dir: this.toolParams.spike, duration: 0, downtime: 3.0,
        });
        return;
      case 'conveyor':
        this.appendTo(page, 'conveyors', { x: col, y: row, dir: this.toolParams.conveyor });
        return;
      case 'cannon':
        this.appendTo(page, 'cannons', {
          x: col, y: row, dir: this.toolParams.cannon,
          period: DEFAULT_CANNON_PERIOD, bullet_speed: DEFAULT_CANNON_BULLET_SPEED,
        });
        return;
      case 'turret':
        this.appendTo(page, 'turrets', {
          x: col, y: row, period: DEFAULT_TURRET_PERIOD, bullet_speed: DEFAULT_TURRET_BULLET_SPEED,
        });
        return;
      case 'laser_cannon': {
        const lc = this.toolParams.laser_cannon;
        this.appendTo(page, 'laser_cannons', {
          x: col, y: row,
          dir: lc.dir,
          rotate: lc.rotate,
          duration: lc.duration,
          downtime: lc.downtime,
        });
        return;
      }
      case 'gear':
        this.appendTo(page, 'gears', {
          x: col, y: row, size: DEFAULT_GEAR_SIZE, speed: DEFAULT_GEAR_SPEED,
          spin: DEFAULT_GEAR_SPIN, waypoints: [], closed: false,
        });
        return;
      case 'portal':
        this.placePortalPoint(page, col, row, this.toolParams.portal);
        return;
      case 'key':
        this.appendTo(page, 'keys', { x: col, y: row, color: this.toolParams.key });
        return;
      case 'key_wall':
        this.appendTo(page, 'key_walls', { x: col, y: row, color: this.toolParams.key_wall });
        return;
      case 'teleport': {
        const max = this.level.pages.length - 1;
        const target = Math.max(0, Math.min(this.toolParams.teleport, max));
        this.appendTo(page, 'teleports', { x: col, y: row, target_page: target });
        return;
      }
      case 'text': {
        const tp = this.toolParams.text;
        // Multi-cell placement: every cell in the bounds must be free
        // (rule #3). The top-left was already checked by the outer
        // applyTool guard, so this re-checks every cell including the
        // top-left to keep the loop simple.
        if (!this.isAreaClearForText(page, col, row, tp.width, tp.height, null)) {
          return;
        }
        this.appendTo(page, 'text_labels', {
          x: col, y: row, width: tp.width, height: tp.height, text: 'Text',
        });
        return;
      }
    }
  }

  // Multi-cell area-clear check used by text-label placement and drag-
  // move. Walks each cell of the proposed bounds, rejecting if any
  // cell is occupied — except cells already inside `excludeText` (the
  // text being moved), which are treated as vacant since the text
  // will leave those positions.
  private isAreaClearForText(
    page: PageData,
    x: number,
    y: number,
    w: number,
    h: number,
    excludeText: TextLabelData | null,
  ): boolean {
    const cols = page.tiles[0]?.length ?? 0;
    const rows = page.tiles.length;
    for (let dy = 0; dy < h; dy++) {
      for (let dx = 0; dx < w; dx++) {
        const cx = x + dx;
        const cy = y + dy;
        if (cx < 0 || cy < 0 || cx >= cols || cy >= rows) return false;
        if (excludeText &&
            cx >= excludeText.x && cx < excludeText.x + excludeText.width &&
            cy >= excludeText.y && cy < excludeText.y + excludeText.height) {
          continue;
        }
        if (this.isOccupied(page, cx, cy)) return false;
      }
    }
    return true;
  }

  // Lazy-init optional element arrays so the saved JSON doesn't carry
  // empty arrays for element types the level doesn't use.
  private appendTo<K extends keyof PageData>(
    page: PageData,
    key: K,
    item: NonNullable<PageData[K]> extends Array<infer U> ? U : never,
  ): void {
    const arr = (page[key] as unknown as unknown[] | undefined) ?? [];
    arr.push(item);
    (page as unknown as Record<string, unknown>)[key as string] = arr;
  }

  // Tile grid is row-major strings; immutable per-row so we slice + reinsert.
  private setTile(page: PageData, col: number, row: number, ch: string): void {
    const r = page.tiles[row]!;
    page.tiles[row] = r.slice(0, col) + ch + r.slice(col + 1);
  }

  // Portals stack: each color holds at most one portal entry, with up to
  // 2 points. First click on a color creates an orphan; second click on
  // the same color pairs it; third+ click on a paired portal replaces the
  // SECOND point (so the first half stays put — feels more like "moving
  // the destination" than reshuffling both halves).
  private placePortalPoint(
    page: PageData,
    col: number,
    row: number,
    color: number,
  ): void {
    if (!page.portals) page.portals = [];
    let portal = page.portals.find((p) => p.color === color);
    if (!portal) {
      portal = { color, points: [] };
      page.portals.push(portal);
    }
    if (portal.points.some((pt) => pt.x === col && pt.y === row)) return;
    if (portal.points.length >= 2) {
      portal.points = [portal.points[0]!, { x: col, y: row }];
    } else {
      portal.points.push({ x: col, y: row });
    }
  }

  // Cell-clear: tile back to '.' and any single-cell element at this cell
  // removed. Multi-cell entities (gears with waypoints, portals with two
  // points) get their HOME / a single point removed; gears keyed off
  // their home cell, portals filter the matching point and prune empty
  // portals. Spawn + exit are NOT erased here — they're global pointers
  // the user must reposition with their respective tools.
  //
  // Cascade: erasing a key whose color has no other keys left in the
  // level also wipes all key_walls of that color (issue #2). Multiple
  // keys of the same color are uncommon but legal — only the LAST key
  // of a color triggers the wall sweep so a stray duplicate-key delete
  // doesn't silently break the rest of the puzzle.
  private eraseAt(page: PageData, col: number, row: number): void {
    const at = (e: { x: number; y: number }) => e.x === col && e.y === row;
    const r = page.tiles[row]!;
    if (r.charAt(col) !== '.') {
      page.tiles[row] = r.slice(0, col) + '.' + r.slice(col + 1);
    }

    // Snapshot key colors at this cell BEFORE removing them so we can
    // run the orphan-walls sweep below.
    const removedKeyColors = page.keys?.filter(at).map((k) => k.color) ?? [];

    if (page.glass_walls)  page.glass_walls  = page.glass_walls.filter((e) => !at(e));
    if (page.spike_blocks) page.spike_blocks = page.spike_blocks.filter((e) => !at(e));
    if (page.spikes)       page.spikes       = page.spikes.filter((e) => !at(e));
    if (page.conveyors)    page.conveyors    = page.conveyors.filter((e) => !at(e));
    if (page.cannons)      page.cannons      = page.cannons.filter((e) => !at(e));
    if (page.key_walls)    page.key_walls    = page.key_walls.filter((e) => !at(e));
    if (page.keys)         page.keys         = page.keys.filter((e) => !at(e));
    if (page.turrets)      page.turrets      = page.turrets.filter((e) => !at(e));
    if (page.laser_cannons) page.laser_cannons = page.laser_cannons.filter((e) => !at(e));
    if (page.teleports)    page.teleports    = page.teleports.filter((e) => !at(e));
    if (page.gears) {
      page.gears = page.gears.filter((g) => !at(g));
      // Drop the path-edit reference if the gear under it just got wiped.
      if (this.gearEditState && !page.gears.includes(this.gearEditState.gear)) {
        this.gearEditState = null;
      }
    }
    if (page.portals) {
      page.portals = page.portals
        .map((p) => ({ ...p, points: p.points.filter((pt) => !at(pt)) }))
        .filter((p) => p.points.length > 0);
    }
    // Text labels: erase any whose bounds rect contains (col, row).
    if (page.text_labels) {
      page.text_labels = page.text_labels.filter(
        (t) => !(col >= t.x && col < t.x + t.width && row >= t.y && row < t.y + t.height),
      );
    }

    for (const color of removedKeyColors) {
      const stillHasKey = this.level.pages.some((pg) =>
        pg.keys?.some((k) => k.color === color),
      );
      if (stillHasKey) continue;
      for (const pg of this.level.pages) {
        if (pg.key_walls) {
          pg.key_walls = pg.key_walls.filter((w) => w.color !== color);
        }
      }
    }

    this.validateSelectedElement();
  }
}
