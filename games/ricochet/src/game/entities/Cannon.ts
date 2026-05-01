import Phaser from 'phaser';

import { COLOR_CANNON, COLOR_CANNON_BARREL, TILE_SIZE } from '../config/feel';
import type { CardinalDir } from '../../shared/level-format/types';
import { Bullet } from './Bullet';

// Fixed cannon: a wall-like static body (player can't pass through it)
// that fires a Bullet every `period` seconds in `dir`. First shot is
// delayed by `period` (NOT 0) so the player has a moment to read the
// room before the first shot — matches the Godot reference.

type DirVector = { x: number; y: number };
const DIR_VECTORS: Record<CardinalDir, DirVector> = {
  up:    { x: 0,  y: -1 },
  down:  { x: 0,  y: 1  },
  left:  { x: -1, y: 0  },
  right: { x: 1,  y: 0  },
};

// Barrel rect per direction. Coords are fractions of TILE_SIZE relative
// to the cell's top-left; the barrel sticks out of the side facing the
// firing direction. Lifted from the Godot _make_cannon helper.
type Rect = { x: number; y: number; w: number; h: number };
const BARREL_RECTS: Record<CardinalDir, Rect> = {
  up:    { x: 0.35, y: 0,    w: 0.30, h: 0.50 },
  down:  { x: 0.35, y: 0.50, w: 0.30, h: 0.50 },
  left:  { x: 0,    y: 0.35, w: 0.50, h: 0.30 },
  right: { x: 0.50, y: 0.35, w: 0.50, h: 0.30 },
};

export class Cannon extends Phaser.GameObjects.Rectangle {
  declare body: Phaser.Physics.Arcade.StaticBody;

  private readonly dir: CardinalDir;
  private readonly period: number;
  private readonly bulletSpeedPx: number;     // cached: tiles → pixels at construction
  private readonly bulletGroup: Phaser.GameObjects.Group;
  private timer: number;

  constructor(
    scene: Phaser.Scene,
    col: number,
    row: number,
    dir: CardinalDir,
    period: number,
    bulletSpeedTiles: number,
    bulletGroup: Phaser.GameObjects.Group,
  ) {
    const x = (col + 0.5) * TILE_SIZE;
    const y = (row + 0.5) * TILE_SIZE;
    super(scene, x, y, TILE_SIZE, TILE_SIZE, COLOR_CANNON);
    scene.add.existing(this);
    scene.physics.add.existing(this, true);  // static body — blocks the player

    this.dir = dir;
    this.period = period;
    this.bulletSpeedPx = bulletSpeedTiles * TILE_SIZE;
    this.bulletGroup = bulletGroup;
    this.timer = period;  // first shot delayed by period

    // Barrel visual (no body — purely cosmetic; the cell-sized cannon
    // body already covers the cell for collision). Sticks out the side
    // facing `dir`.
    const cellTL = { x: x - TILE_SIZE * 0.5, y: y - TILE_SIZE * 0.5 };
    const r = BARREL_RECTS[dir];
    scene.add.rectangle(
      cellTL.x + (r.x + r.w * 0.5) * TILE_SIZE,
      cellTL.y + (r.y + r.h * 0.5) * TILE_SIZE,
      r.w * TILE_SIZE,
      r.h * TILE_SIZE,
      COLOR_CANNON_BARREL,
    );
  }

  // Called by PlayScene each frame.
  tick(dt: number): void {
    this.timer -= dt;
    if (this.timer <= 0) {
      this.timer = this.period;
      this.fire();
    }
  }

  private fire(): void {
    const v = DIR_VECTORS[this.dir];
    // Spawn just outside the cannon's cell in the firing direction so the
    // bullet doesn't immediately overlap its own cannon (which would
    // self-despawn). Cardinal-only fire makes a flat offset sufficient;
    // the ignoreBody pattern in Bullet handles oblique-fire turrets later.
    const offset = TILE_SIZE * 0.5 + Bullet.SIZE * 0.5 + 1;
    const bx = this.x + v.x * offset;
    const by = this.y + v.y * offset;
    const bullet = new Bullet(this.scene, bx, by, v.x * this.bulletSpeedPx, v.y * this.bulletSpeedPx);
    this.bulletGroup.add(bullet);
  }
}
