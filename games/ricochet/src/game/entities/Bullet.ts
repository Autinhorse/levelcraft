import Phaser from 'phaser';

import { COLOR_BULLET } from '../config/feel';

// Projectile fired by Cannons (and, in a later phase, Turrets). Travels
// at constant velocity (no gravity, no drag). Killed by:
//  - Overlap with the player → kills the player + despawns
//  - Overlap with any wall-like static body → despawns silently
//  - Lifetime timeout (safety net for bullets that somehow miss every wall)
//
// `ignoreBody` + `ignoreTimer` is the self-ignore pattern lifted from
// the Godot turret port: the SHOOTER passes itself in so its own
// bullet doesn't despawn against it at oblique firing angles where the
// bullet's bbox briefly overlaps the shooter's cell at spawn time.
// Cannons fire on cardinal axes so they never need it; turrets will.

const BULLET_SIZE = 14;

export class Bullet extends Phaser.GameObjects.Rectangle {
  declare body: Phaser.Physics.Arcade.Body;

  static readonly SIZE = BULLET_SIZE;

  ignoreBody: Phaser.GameObjects.GameObject | null = null;
  ignoreTimer = 0;          // seconds remaining where ignoreBody is exempt
  private lifetime = 5;     // seconds — safety net so stray bullets self-clean

  constructor(scene: Phaser.Scene, x: number, y: number, vx: number, vy: number) {
    super(scene, x, y, BULLET_SIZE, BULLET_SIZE, COLOR_BULLET);
    scene.add.existing(this);
    scene.physics.add.existing(this);
    this.body.setAllowGravity(false);
    this.body.setVelocity(vx, vy);
  }

  // Called by PlayScene each frame. Decrements timers; auto-destroys on
  // lifetime expiry so a bullet that escapes the playable area can't
  // accumulate.
  tick(dt: number): void {
    if (this.ignoreTimer > 0) {
      this.ignoreTimer -= dt;
    }
    this.lifetime -= dt;
    if (this.lifetime <= 0) {
      this.destroy();
    }
  }
}
