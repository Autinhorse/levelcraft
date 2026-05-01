import Phaser from 'phaser';

import { COLOR_GEAR, COLOR_GEAR_HUB, COLOR_GEAR_SPOKE } from '../config/feel';

// Path-following hazard. Built as a Container so the disc + spokes + hub
// can all rotate together via Container.rotation. Movement is authored:
// `path[0]` is the gear's home, subsequent entries are waypoints.
//
// Open paths PING-PONG: home → wp1 → wp2 → … → wpN → wpN-1 → … → wp1 →
// home → wp1 → … (reverses at each endpoint).
// Closed paths CYCLE: home → wp1 → wp2 → … → wpN → home → wp1 → …
//
// Killing the player uses Phaser's overlap (set up in PlayScene). Gears
// have no wall behavior — bullets pass through them, mirroring the
// Godot collision_mask=2 (player only) configuration.

export class Gear extends Phaser.GameObjects.Container {
  declare body: Phaser.Physics.Arcade.Body;

  private readonly speedPx: number;       // pixels per second along the path
  private readonly spinSpeed: number;     // rotation rate, rad/sec
  private readonly path: ReadonlyArray<Phaser.Math.Vector2>;
  private readonly closed: boolean;

  // Open-path direction; +1 forward through indices, -1 backward.
  // Ignored when closed (cycles always go forward).
  private direction: 1 | -1 = 1;
  // The path index the gear is currently moving toward.
  private nextIndex = 0;

  constructor(
    scene: Phaser.Scene,
    homeX: number,
    homeY: number,
    radiusPx: number,
    speedPx: number,
    spinSpeed: number,
    path: ReadonlyArray<Phaser.Math.Vector2>,
    closed: boolean,
  ) {
    super(scene, homeX, homeY);
    scene.add.existing(this);

    // Build visual (children rotate with the container).
    // Disc.
    this.add(scene.add.circle(0, 0, radiusPx, COLOR_GEAR));
    // Spokes — a "+" inside the disc, slightly inset so it reads as
    // gear teeth even at small zoom.
    const spokes = scene.add.graphics();
    spokes.lineStyle(3, COLOR_GEAR_SPOKE, 1);
    const reach = radiusPx * 0.9;
    spokes.lineBetween(-reach, 0, reach, 0);
    spokes.lineBetween(0, -reach, 0, reach);
    this.add(spokes);
    // Center hub (bright accent so the spin is visible).
    this.add(scene.add.circle(0, 0, radiusPx * 0.22, COLOR_GEAR_HUB));

    // Physics body — circular, centered on the container's origin.
    // setCircle's offset is from the body's TOP-LEFT corner, so to
    // center the circle of radius r on the container's (0,0), the
    // offset must be (-r, -r).
    scene.physics.add.existing(this);
    this.body.setCircle(radiusPx, -radiusPx, -radiusPx);
    this.body.setAllowGravity(false);

    this.speedPx = speedPx;
    this.spinSpeed = spinSpeed;
    this.path = path;
    this.closed = closed;
    if (path.length >= 2) {
      this.nextIndex = 1;  // start by moving toward the first waypoint
    }
  }

  // Called by PlayScene each frame. Spins the visual + advances along
  // the path. Position is set directly (the body syncs via Container's
  // gameObject reference); body has no velocity so no integration fight.
  tick(dt: number): void {
    this.rotation += this.spinSpeed * dt;
    if (this.path.length < 2 || this.speedPx <= 0) {
      return;
    }

    const target = this.path[this.nextIndex]!;
    const dx = target.x - this.x;
    const dy = target.y - this.y;
    const distSq = dx * dx + dy * dy;
    const step = this.speedPx * dt;

    if (distSq <= step * step) {
      // Arrived (or would overshoot this frame). Snap and pick the next index.
      this.x = target.x;
      this.y = target.y;
      this.advanceIndex();
    } else {
      const dist = Math.sqrt(distSq);
      this.x += (dx / dist) * step;
      this.y += (dy / dist) * step;
    }
  }

  private advanceIndex(): void {
    if (this.closed) {
      this.nextIndex = (this.nextIndex + 1) % this.path.length;
      return;
    }
    // Open path — flip direction at each endpoint, then step.
    if (this.nextIndex === this.path.length - 1) {
      this.direction = -1;
    } else if (this.nextIndex === 0) {
      this.direction = 1;
    }
    this.nextIndex += this.direction;
    // Clamp defensively in case path.length < 2 was somehow violated.
    if (this.nextIndex < 0) this.nextIndex = 0;
    if (this.nextIndex >= this.path.length) this.nextIndex = this.path.length - 1;
  }
}
