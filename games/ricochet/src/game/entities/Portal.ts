import Phaser from 'phaser';

import {
  KEY_COLORS_DARK,
  KEY_COLORS_LIGHT,
  PORTAL_COOLDOWN_SEC,
  TILE_SIZE,
} from '../config/feel';
import type { Player } from './Player';

// One half of a paired teleporter. Built as a Container holding an outer
// dark ring + inner bright core (both in the pair's color) so the two
// halves of a pair are visually obvious at a glance.
//
// On player overlap: teleport the player to `partner.position`, preserving
// velocity (a fast-moving player exits going the same direction). Both
// portals enter a brief cooldown (body.enable = false) afterward, so the
// player materializing inside the partner doesn't immediately re-teleport.
//
// Orphan portals (pair with only 1 point) have partner = null and are
// non-functional — they exist visually but never teleport. This matches
// the Godot editor's "place one half then walk away" → orphan flow.

export class Portal extends Phaser.GameObjects.Container {
  declare body: Phaser.Physics.Arcade.StaticBody;

  partner: Portal | null = null;
  private cooldownTimer = 0;

  constructor(scene: Phaser.Scene, col: number, row: number, colorIdx: number) {
    const x = (col + 0.5) * TILE_SIZE;
    const y = (row + 0.5) * TILE_SIZE;
    super(scene, x, y);
    scene.add.existing(this);

    const light = KEY_COLORS_LIGHT[colorIdx] ?? 0xffffff;
    const dark = KEY_COLORS_DARK[colorIdx] ?? 0x444444;
    // Outer ring (dark variant) + inner core (light variant) — reads as
    // a portal "lens" rather than a flat tile.
    this.add(scene.add.circle(0, 0, TILE_SIZE * 0.45, dark));
    this.add(scene.add.circle(0, 0, TILE_SIZE * 0.30, light));

    // Static body — portal doesn't move. setCircle's offset is from the
    // body's top-left corner, so to center the circle on the container's
    // (0, 0) the offset must be (-r, -r).
    const bodyR = TILE_SIZE * 0.40;
    scene.physics.add.existing(this, true);
    this.body.setCircle(bodyR, -bodyR, -bodyR);
  }

  // Player-overlap callback (registered in PlayScene).
  // No-ops if on cooldown or unpaired (orphan).
  handlePlayerOverlap(player: Player): void {
    if (this.cooldownTimer > 0 || this.partner === null) {
      return;
    }
    // Preserve velocity so a fast-moving player carries momentum through
    // the portal — body.reset zeros it, so we capture and restore.
    const vx = player.body.velocity.x;
    const vy = player.body.velocity.y;
    player.body.reset(this.partner.x, this.partner.y);
    player.body.setVelocity(vx, vy);

    // Both portals get the cooldown so the partner doesn't immediately
    // re-trigger as the player appears inside it.
    this.armCooldown();
    this.partner.armCooldown();
  }

  // Per-frame: count down cooldown and re-enable when it expires.
  tick(dt: number): void {
    if (this.cooldownTimer > 0) {
      this.cooldownTimer -= dt;
      if (this.cooldownTimer <= 0) {
        this.body.enable = true;
      }
    }
  }

  private armCooldown(): void {
    this.cooldownTimer = PORTAL_COOLDOWN_SEC;
    this.body.enable = false;
  }
}
