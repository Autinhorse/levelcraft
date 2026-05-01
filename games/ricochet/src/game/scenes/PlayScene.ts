import Phaser from 'phaser';

import {
  TILE_SIZE,
  COLOR_WALL,
  COLOR_SPIKE,
  COLOR_SPIKE_PLATE,
  COLOR_BACKGROUND,
  COLOR_GRID,
  DEFAULT_LEVEL_URL,
  DEFAULT_PAGE_INDEX,
} from '../config/feel';
import { Player, PlayerState } from '../entities/Player';
import { validateLevel } from '../../shared/level-format/load';
import type { CardinalDir, PageData } from '../../shared/level-format/types';

// Spike rect layout per direction. Each cell splits into:
//   - A "plate" (wall — blocks the player, mounts the spikes)
//   - A "spike" (hazard — kills the player on overlap)
//   - Air (the open side the spikes point into)
// Coords are fractions of TILE_SIZE, origin at the cell's top-left. The
// plate's solid body is added first; the spike's hazard body sits on top
// (visually + collision-wise). For 'up' the lethal points stick UP into
// the cell's top-air; for 'right' they stick RIGHT, etc.
type Rect = { x: number; y: number; w: number; h: number };
const SPIKE_LAYOUT: Record<CardinalDir, { plate: Rect; spike: Rect }> = {
  up:    { plate: { x: 0,   y: 0.8, w: 1,   h: 0.2 }, spike: { x: 0,   y: 0.4, w: 1,   h: 0.4 } },
  down:  { plate: { x: 0,   y: 0,   w: 1,   h: 0.2 }, spike: { x: 0,   y: 0.2, w: 1,   h: 0.4 } },
  left:  { plate: { x: 0.8, y: 0,   w: 0.2, h: 1   }, spike: { x: 0.4, y: 0,   w: 0.4, h: 1   } },
  right: { plate: { x: 0,   y: 0,   w: 0.2, h: 1   }, spike: { x: 0,   y: 0,   w: 0.4, h: 1   } },
};

const LEVEL_KEY = 'level-default';

// Phase 3: data-driven test scene. Loads the default level JSON in
// preload(), reads page DEFAULT_PAGE_INDEX in create(), builds walls
// from the tile grid, spawns the player at page.spawn. The room is
// centered horizontally in the design viewport so smaller pages
// (Godot's default page is 25x20 = 1200x960) sit cleanly inside the
// 1600x960 design space without ugly empty bars on one side.
//
// Optional element arrays (spikes, gears, portals, …) are present in the
// loaded JSON but not yet consumed — those land in Phases 4+.
export class PlayScene extends Phaser.Scene {
  private player!: Player;
  private walls!: Phaser.Physics.Arcade.StaticGroup;
  private hazards!: Phaser.Physics.Arcade.StaticGroup;
  private debugText!: Phaser.GameObjects.Text;

  constructor() {
    super('PlayScene');
  }

  preload(): void {
    this.load.json(LEVEL_KEY, DEFAULT_LEVEL_URL);
  }

  create(): void {
    this.cameras.main.setBackgroundColor(COLOR_BACKGROUND);

    const raw = this.cache.json.get(LEVEL_KEY) as unknown;
    const level = validateLevel(raw, DEFAULT_LEVEL_URL);
    const page = level.pages[DEFAULT_PAGE_INDEX];
    if (!page) {
      throw new Error(`Level has no page index ${DEFAULT_PAGE_INDEX}`);
    }

    const cols = page.tiles[0]!.length;
    const rows = page.tiles.length;

    // Center the room within the 1600x960 design viewport. Camera
    // scrollX = -offsetX makes world (0,0) appear at screen (offsetX, 0).
    const offsetX = (this.scale.gameSize.width - cols * TILE_SIZE) / 2;
    const offsetY = (this.scale.gameSize.height - rows * TILE_SIZE) / 2;
    this.cameras.main.setScroll(-offsetX, -offsetY);

    this.drawGridBackground(cols, rows);
    this.ensureWallTexture();

    this.walls = this.physics.add.staticGroup();
    this.hazards = this.physics.add.staticGroup();
    this.buildWalls(page);
    this.buildSpikes(page);

    // Input wiring — the player gets references to the cursor keys and
    // jump key so it doesn't have to reach into the scene's input plugin.
    const keyboard = this.input.keyboard;
    if (!keyboard) {
      throw new Error('PlayScene requires the keyboard plugin');
    }
    const cursors = keyboard.createCursorKeys();
    const jumpKey = keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.SPACE);

    const spawnX = (page.spawn.x + 0.5) * TILE_SIZE;
    const spawnY = (page.spawn.y + 0.5) * TILE_SIZE;
    this.player = new Player(this, spawnX, spawnY, cursors, jumpKey);

    this.physics.add.collider(this.player, this.walls);
    this.physics.add.overlap(this.player, this.hazards, () => this.player.die());

    // HUD — anchored to the screen, not the world, so it doesn't move
    // when the camera scrolls (setScrollFactor(0) is the standard idiom).
    this.add
      .text(
        16,
        this.scale.gameSize.height - 28,
        `${level.name}  |  Arrows: launch  |  Space: jump  |  Phase 3 — JSON loader`,
        { color: '#9aa0a8', fontSize: '14px' },
      )
      .setScrollFactor(0);

    this.debugText = this.add
      .text(16, 16, '', {
        color: '#cccccc',
        fontSize: '14px',
        fontFamily: 'monospace',
      })
      .setScrollFactor(0);
  }

  update(time: number, delta: number): void {
    this.player.update(time, delta);

    const t = this.player.body.touching;
    const b = this.player.body.blocked;
    this.debugText.setText([
      `state: ${PlayerState[this.player.state]}`,
      `vel: (${this.player.body.velocity.x.toFixed(0)}, ${this.player.body.velocity.y.toFixed(0)})`,
      `touching: ${t.up ? 'U' : '-'}${t.down ? 'D' : '-'}${t.left ? 'L' : '-'}${t.right ? 'R' : '-'}`,
      `blocked:  ${b.up ? 'U' : '-'}${b.down ? 'D' : '-'}${b.left ? 'L' : '-'}${b.right ? 'R' : '-'}`,
    ]);
  }

  private buildWalls(page: PageData): void {
    for (let r = 0; r < page.tiles.length; r++) {
      const row = page.tiles[r]!;
      for (let c = 0; c < row.length; c++) {
        const ch = row.charAt(c);
        if (ch === 'W') {
          this.makeWall(c, r);
        }
        // 'C' (coin), '.' (empty), and any other chars are ignored for
        // now — Phase 5+ will hook them into their respective builders.
      }
    }
  }

  private makeWall(col: number, row: number): void {
    const x = (col + 0.5) * TILE_SIZE;
    const y = (row + 0.5) * TILE_SIZE;
    this.walls.create(x, y, 'wall');
  }

  private buildSpikes(page: PageData): void {
    if (!page.spikes) {
      return;
    }
    for (const spike of page.spikes) {
      this.makeSpike(spike.x, spike.y, spike.dir);
    }
  }

  private makeSpike(col: number, row: number, dir: CardinalDir): void {
    const layout = SPIKE_LAYOUT[dir];
    // Plate first (visually beneath the spike where they overlap), spike on top.
    this.makeSpikePart(col, row, layout.plate, COLOR_SPIKE_PLATE, /* hazard= */ false);
    this.makeSpikePart(col, row, layout.spike, COLOR_SPIKE, /* hazard= */ true);
  }

  private makeSpikePart(
    col: number,
    row: number,
    rect: Rect,
    color: number,
    hazard: boolean,
  ): void {
    const w = rect.w * TILE_SIZE;
    const h = rect.h * TILE_SIZE;
    const x = col * TILE_SIZE + rect.x * TILE_SIZE + w / 2;
    const y = row * TILE_SIZE + rect.y * TILE_SIZE + h / 2;

    const visual = this.add.rectangle(x, y, w, h, color);
    const group = hazard ? this.hazards : this.walls;
    group.add(visual);
    // After group.add gives the rect a static body, sync the body's size
    // to the rect's actual dimensions (default static body uses display
    // size — usually fine, but be explicit so future layout changes can't
    // bite us).
    const body = visual.body as Phaser.Physics.Arcade.StaticBody;
    body.setSize(w, h);
    body.updateFromGameObject();
  }

  private ensureWallTexture(): void {
    if (this.textures.exists('wall')) {
      return;
    }
    const gfx = this.add.graphics();
    gfx.fillStyle(COLOR_WALL, 1);
    gfx.fillRect(0, 0, TILE_SIZE, TILE_SIZE);
    gfx.generateTexture('wall', TILE_SIZE, TILE_SIZE);
    gfx.destroy();
  }

  private drawGridBackground(cols: number, rows: number): void {
    const gfx = this.add.graphics();
    gfx.lineStyle(1, COLOR_GRID, 0.6);
    const w = cols * TILE_SIZE;
    const h = rows * TILE_SIZE;
    for (let x = 0; x <= w; x += TILE_SIZE) {
      gfx.lineBetween(x, 0, x, h);
    }
    for (let y = 0; y <= h; y += TILE_SIZE) {
      gfx.lineBetween(0, y, w, y);
    }
    gfx.setDepth(-100);
  }
}
