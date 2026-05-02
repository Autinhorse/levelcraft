import Phaser from 'phaser';

import {
  COLOR_LASER_BEAM,
  COLOR_LASER_CANNON,
  COLOR_LASER_CANNON_BARREL,
  COLOR_LASER_HUB,
  LASER_BEAM_THICKNESS_TILES,
  LASER_ROTATION_SPEED,
  TILE_SIZE,
} from '../config/feel';
import type { CardinalDir, LaserRotateMode } from '../../shared/level-format/types';
import type { Gear } from './Gear';

// Laser cannon. Wall-like static body (blocks the player like cannon /
// turret) with a rotating barrel and a beam that extends from the
// barrel tip until it hits a blocker.
//
// Three modes per data:
//   non-rotating          → barrel stays at its initial direction
//   clockwise / ccw       → barrel rotates continuously
//
// Two timing parameters:
//   duration > 0          → cycle: ON for `duration`, OFF for `downtime`
//   duration === 0        → always ON (continuous fire)
//
// Player kill detection is a manual line-segment-vs-AABB test in
// checkPlayerHit() — Phaser arcade physics doesn't do rotated bodies,
// and the beam can be at arbitrary angles in cw / ccw modes.

const DIR_TO_RAD: Record<CardinalDir, number> = {
  right: 0,
  down: Math.PI / 2,
  left: Math.PI,
  up: -Math.PI / 2,
};

// Closure that returns true if (col, row) blocks the beam. Owned by
// PlayScene so the laser can defer the "what counts as a wall" rule
// to the live state (handles glass walls broken mid-play, key walls
// removed after key pickup, etc.).
export type BeamBlockerCheck = (col: number, row: number) => boolean;

export class LaserCannon extends Phaser.GameObjects.Container {
  declare body: Phaser.Physics.Arcade.StaticBody;

  private readonly barrel: Phaser.GameObjects.Container;
  private readonly beam: Phaser.GameObjects.Graphics;
  private readonly rotateMode: LaserRotateMode;
  private readonly duration: number;
  private readonly downtime: number;
  private readonly isBlocker: BeamBlockerCheck;
  private readonly beamThicknessPx: number;
  // Cell coordinates of the cannon itself — excluded from blocker
  // checks so the beam never reads its own cell as a wall (it would,
  // since the cannon is added to the walls group).
  private readonly selfCol: number;
  private readonly selfRow: number;
  // Live gear list. Read each frame so beam clipping reflects gear
  // movement along the path. The reference is shared with PlayScene;
  // we don't mutate it.
  private readonly gears: ReadonlyArray<Gear>;

  // Phase state. `firing` follows the duty cycle; ignored when
  // duration === 0 (always firing). `phaseTimer` counts down the
  // current phase's remaining time.
  private firing = true;
  private phaseTimer: number;

  // Cached endpoints for the most recent tick — used by checkPlayerHit
  // so we don't recompute the raycast for the player test.
  private startX = 0;
  private startY = 0;
  private endX = 0;
  private endY = 0;

  constructor(
    scene: Phaser.Scene,
    col: number,
    row: number,
    initialDir: CardinalDir,
    rotateMode: LaserRotateMode,
    duration: number,
    downtime: number,
    isBlocker: BeamBlockerCheck,
    gears: ReadonlyArray<Gear>,
  ) {
    const x = (col + 0.5) * TILE_SIZE;
    const y = (row + 0.5) * TILE_SIZE;
    super(scene, x, y);
    scene.add.existing(this);

    // Base — full cell, axis-aligned.
    this.add(scene.add.rectangle(0, 0, TILE_SIZE, TILE_SIZE, COLOR_LASER_CANNON));

    // Barrel sub-container. Rotation 0 = pointing right; we set the
    // initial angle from `initialDir` below.
    this.barrel = new Phaser.GameObjects.Container(scene, 0, 0);
    this.add(this.barrel);
    this.barrel.add(
      scene.add.rectangle(
        TILE_SIZE * 0.30,
        0,
        TILE_SIZE * 0.60,
        TILE_SIZE * 0.20,
        COLOR_LASER_CANNON_BARREL,
      ),
    );
    this.barrel.add(scene.add.circle(0, 0, TILE_SIZE * 0.16, COLOR_LASER_HUB));
    this.barrel.rotation = DIR_TO_RAD[initialDir];

    // Beam — scene-level Graphics, drawn each tick in world coords.
    // Depth lifts it above the per-page render container so the beam
    // is visible over walls and entities.
    this.beam = scene.add.graphics();
    this.beam.setDepth(50);
    this.beamThicknessPx = TILE_SIZE * LASER_BEAM_THICKNESS_TILES;

    // Static body — wall-like, same pattern as Turret.
    scene.physics.add.existing(this, true);
    this.body.setSize(TILE_SIZE, TILE_SIZE);
    this.body.position.set(this.x - TILE_SIZE / 2, this.y - TILE_SIZE / 2);

    this.rotateMode = rotateMode;
    this.duration = duration;
    this.downtime = downtime;
    this.isBlocker = isBlocker;
    this.selfCol = col;
    this.selfRow = row;
    this.gears = gears;

    // Boot in the firing phase. duration === 0 means continuous; we use
    // +Infinity so the timer never elapses.
    this.firing = true;
    this.phaseTimer = duration > 0 ? duration : Number.POSITIVE_INFINITY;
  }

  tick(dt: number): void {
    // Rotate the barrel. The visual barrel-rect spins; the beam follows
    // because we read this.barrel.rotation in updateBeam().
    if (this.rotateMode === 'cw') {
      this.barrel.rotation += LASER_ROTATION_SPEED * dt;
    } else if (this.rotateMode === 'ccw') {
      this.barrel.rotation -= LASER_ROTATION_SPEED * dt;
    }

    // Advance the duty cycle, but only when duration > 0 — otherwise
    // we stay firing forever (timer is +Infinity at construction).
    if (this.duration > 0) {
      this.phaseTimer -= dt;
      if (this.phaseTimer <= 0) {
        this.firing = !this.firing;
        this.phaseTimer = this.firing ? this.duration : this.downtime;
      }
    }

    if (this.firing) {
      this.updateBeam();
    } else {
      this.beam.clear();
    }
  }

  // True if the beam is currently on AND the segment intersects the
  // player AABB (or grazes within half-thickness of it). PlayScene
  // calls this each frame and triggers death.
  checkPlayerHit(player: Phaser.GameObjects.GameObject & { body: Phaser.Physics.Arcade.Body }): boolean {
    if (!this.firing) return false;
    // Player as an AABB centered on player.body.center, padded by half
    // the beam thickness so beam-edge grazes register as hits too.
    const pad = this.beamThicknessPx / 2;
    const left = player.body.x - pad;
    const right = player.body.x + player.body.width + pad;
    const top = player.body.y - pad;
    const bottom = player.body.y + player.body.height + pad;
    return segmentIntersectsRect(
      this.startX, this.startY, this.endX, this.endY,
      left, top, right, bottom,
    );
  }

  destroy(fromScene?: boolean): void {
    this.beam.destroy();
    super.destroy(fromScene);
  }

  // Casts the beam, caches the endpoints, renders it. Two stages:
  //   1. cell raycast — walks in 0.25-tile steps until a blocker cell
  //      OR the level edge is reached. The cannon's own cell is always
  //      skipped (the cannon sits in the walls group, so without this
  //      it would self-block at oblique angles where the start lies
  //      inside its own cell).
  //   2. gear clip — line-vs-circle test against each gear; if a gear
  //      is hit closer than the cell-blocker, the beam ends at the
  //      gear's circle boundary. Cell raycast alone would clip to the
  //      gear's grid cell which is visibly wrong for round gears.
  //
  // Portals + coins + keys + directional spikes + conveyors + the
  // player are not in any blocker group, so they're transparent to
  // the beam by construction (no special-case needed here).
  private updateBeam(): void {
    const angle = this.barrel.rotation;
    const dx = Math.cos(angle);
    const dy = Math.sin(angle);

    // Cell-boundary start — TILE_SIZE/2 along the cardinal axis with
    // larger |component|. At 0° / 90° this is 24 px (cell edge); at
    // 45° this is 24/√(½) ≈ 33.94 px (cell corner). Always lands
    // exactly on the cannon-cell boundary, so the visible beam never
    // overlaps the cannon body.
    const maxComp = Math.max(Math.abs(dx), Math.abs(dy));
    const startOffset = (TILE_SIZE * 0.5) / Math.max(maxComp, 1e-6);
    this.startX = this.x + dx * startOffset;
    this.startY = this.y + dy * startOffset;

    // Stage 1: cell raycast.
    const maxRange = TILE_SIZE * 64;
    const stepSize = TILE_SIZE * 0.25;
    const steps = Math.ceil(maxRange / stepSize);

    let endX = this.startX + dx * maxRange;
    let endY = this.startY + dy * maxRange;
    for (let i = 1; i <= steps; i++) {
      const t = i * stepSize;
      const px = this.startX + dx * t;
      const py = this.startY + dy * t;
      const col = Math.floor(px / TILE_SIZE);
      const row = Math.floor(py / TILE_SIZE);
      if (col === this.selfCol && row === this.selfRow) {
        // Skip self-cell — the cannon is in the walls group, so
        // isBlocker would say "wall here" otherwise. Continue stepping.
        continue;
      }
      if (this.isBlocker(col, row)) {
        endX = px;
        endY = py;
        break;
      }
    }

    // Stage 2: gear clip. lineCircleEntryT returns the smallest t > 0
    // at which the ray enters each gear's circle, or null. Take the
    // minimum across all gears AND the cell-end distance.
    let beamLen = Math.hypot(endX - this.startX, endY - this.startY);
    for (const gear of this.gears) {
      const t = lineCircleEntryT(this.startX, this.startY, dx, dy, gear.x, gear.y, gear.radiusPx);
      if (t !== null && t < beamLen) {
        beamLen = t;
        endX = this.startX + dx * t;
        endY = this.startY + dy * t;
      }
    }

    this.endX = endX;
    this.endY = endY;

    this.beam.clear();
    this.beam.lineStyle(this.beamThicknessPx, COLOR_LASER_BEAM, 1);
    this.beam.lineBetween(this.startX, this.startY, this.endX, this.endY);
  }
}

// Returns the smallest t ≥ 0 along the unit-direction ray
// (sx + t·dx, sy + t·dy) at which the ray enters the circle centered
// at (cx, cy) with radius `r`. null if the ray misses the circle.
// If the ray STARTS inside the circle (start is closer to center than
// r), returns 0 — beam terminates immediately at start, treating the
// gear as opaque even when the cannon is implausibly placed inside it.
function lineCircleEntryT(
  sx: number, sy: number,
  dx: number, dy: number,
  cx: number, cy: number,
  r: number,
): number | null {
  // |start + t*dir - center|² = r²  →  t² + 2(v·dir) t + (v·v − r²) = 0
  // where v = start − center, |dir| = 1.
  const vx = sx - cx;
  const vy = sy - cy;
  const b = 2 * (vx * dx + vy * dy);
  const c = vx * vx + vy * vy - r * r;
  if (c <= 0) return 0;  // start at or inside circle
  const disc = b * b - 4 * c;
  if (disc < 0) return null;
  const sqrtDisc = Math.sqrt(disc);
  // c > 0 means we're outside; both roots have the same sign as -b/2.
  // Smaller root is the entry point. Reject if behind start.
  const t1 = (-b - sqrtDisc) / 2;
  if (t1 < 0) return null;
  return t1;
}

// Standard Liang-Barsky-flavored test: does the segment (x1,y1)-(x2,y2)
// intersect the AABB? Returns true on any overlap, including the
// segment fully inside the rect.
function segmentIntersectsRect(
  x1: number, y1: number, x2: number, y2: number,
  rx1: number, ry1: number, rx2: number, ry2: number,
): boolean {
  // Quick accept: either endpoint inside.
  if (x1 >= rx1 && x1 <= rx2 && y1 >= ry1 && y1 <= ry2) return true;
  if (x2 >= rx1 && x2 <= rx2 && y2 >= ry1 && y2 <= ry2) return true;

  // Quick reject: bounding box of segment doesn't overlap rect.
  const sx1 = Math.min(x1, x2);
  const sx2 = Math.max(x1, x2);
  const sy1 = Math.min(y1, y2);
  const sy2 = Math.max(y1, y2);
  if (sx2 < rx1 || sx1 > rx2 || sy2 < ry1 || sy1 > ry2) return false;

  // Liang-Barsky: clip parametric form against each rect edge.
  const dx = x2 - x1;
  const dy = y2 - y1;
  let tMin = 0;
  let tMax = 1;
  const clip = (p: number, q: number): boolean => {
    if (p === 0) return q >= 0;  // parallel to edge — accept iff inside
    const r = q / p;
    if (p < 0) {
      if (r > tMax) return false;
      if (r > tMin) tMin = r;
    } else {
      if (r < tMin) return false;
      if (r < tMax) tMax = r;
    }
    return true;
  };
  return (
    clip(-dx, x1 - rx1) &&
    clip(dx, rx2 - x1) &&
    clip(-dy, y1 - ry1) &&
    clip(dy, ry2 - y1)
  );
}
