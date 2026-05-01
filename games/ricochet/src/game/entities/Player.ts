import Phaser from 'phaser';

import {
  TILE_SIZE,
  FLIGHT_SPEED_TILES,
  GRAVITY_TILES,
  TERMINAL_VELOCITY_TILES,
  JUMP_HEIGHT_TILES,
  REBOUND_DISTANCE_TILES,
  PAUSE_TIME_SEC,
  DEATH_IMMUNITY_SEC,
  COLOR_PLAYER,
} from '../config/feel';

// Player state machine. Mirrors the Godot version's State enum 1:1 so the
// port can be validated by side-by-side comparison. See player.gd in
// games/ricochet/godot/scripts/ for the reference implementation.
export enum PlayerState {
  IDLE,           // standing on a floor, accepting input
  RISING,         // rising 1 tile vertically before a horizontal launch
  FLYING_H,       // cruising left or right at flight speed
  FLYING_UP,      // cruising up at flight speed
  FLYING_DOWN,    // cruising down at flight speed (only triggered mid-jump)
  JUMPING,        // vertical jump arc; input accepted during ascent AND descent
  REBOUNDING,     // 1-tile horizontal rebound after hitting a wall
  PAUSED,         // brief delay before falling under gravity
  FALLING,        // gravity-driven free fall, no input
  FALLING_INPUT,  // gravity-driven fall after a fly-up ceiling bump; input accepted
}

// Per-state collision rect sizes. Narrowed by 2px on the perpendicular
// axis during motion so the box doesn't snag on the corner of an adjacent
// wall while sliding along it. Lifted from player.gd's _SHAPE_* constants.
const SHAPE_FULL  = { w: TILE_SIZE - 2, h: TILE_SIZE - 2 };
const SHAPE_HMOVE = { w: TILE_SIZE - 2, h: TILE_SIZE - 4 };
const SHAPE_VMOVE = { w: TILE_SIZE - 4, h: TILE_SIZE - 2 };

// States that should be subject to engine gravity. All others use flat /
// authored motion (we set velocity directly each frame and disable gravity
// so the engine doesn't fight us).
const GRAVITY_STATES = new Set<PlayerState>([
  PlayerState.IDLE,           // gravity keeps the body pressed to the floor
  PlayerState.JUMPING,        // gravity creates the natural arc
  PlayerState.FALLING,
  PlayerState.FALLING_INPUT,
]);

export class Player extends Phaser.GameObjects.Rectangle {
  // Narrow body type — set in constructor via physics.add.existing.
  declare body: Phaser.Physics.Arcade.Body;

  state: PlayerState = PlayerState.IDLE;

  // Pixel-space tuning, cached from feel.ts at construction.
  private readonly flightSpeed: number;
  private readonly terminalVelocity: number;
  private readonly reboundDistance: number;
  // Initial up-velocity to reach jumpHeight under gravity: v = sqrt(2 * g * h).
  private readonly jumpInitialVelocity: number;
  // Physics step dt (fixed, NOT scene render dt). Used by REBOUNDING /
  // RISING to compute a per-step velocity that lands exactly on target
  // without overshoot, regardless of render frame rate.
  private readonly physicsDt: number;

  // Per-state working values.
  private direction = 0;            // -1 left, 0, +1 right
  private riseTargetY = 0;          // y-coord to stop the pre-launch rise at
  private reboundTargetX = 0;       // x-coord to stop the rebound at
  private pauseTimer = 0;
  private postPauseState: PlayerState = PlayerState.FALLING;
  // Brief immunity after dying — debounces double-deaths from multiple
  // overlapping hazard bodies in the same frame, and gives the player a
  // moment at spawn before any spawn-adjacent hazard re-kills them.
  private dyingTimer = 0;
  // Original spawn coordinates, captured at construction. die() teleports
  // the body back here.
  private readonly spawnPosition: Phaser.Math.Vector2;

  // Input refs — passed in by PlayScene so the player doesn't reach into
  // the scene's input plugin directly.
  private readonly cursors: Phaser.Types.Input.Keyboard.CursorKeys;
  private readonly jumpKey: Phaser.Input.Keyboard.Key;

  constructor(
    scene: Phaser.Scene,
    x: number,
    y: number,
    cursors: Phaser.Types.Input.Keyboard.CursorKeys,
    jumpKey: Phaser.Input.Keyboard.Key,
  ) {
    super(scene, x, y, TILE_SIZE, TILE_SIZE, COLOR_PLAYER);
    scene.add.existing(this);
    scene.physics.add.existing(this);

    this.cursors = cursors;
    this.jumpKey = jumpKey;
    this.spawnPosition = new Phaser.Math.Vector2(x, y);

    // Cache pixel values from tile units.
    this.flightSpeed = FLIGHT_SPEED_TILES * TILE_SIZE;
    this.terminalVelocity = TERMINAL_VELOCITY_TILES * TILE_SIZE;
    this.reboundDistance = REBOUND_DISTANCE_TILES * TILE_SIZE;
    const gravity = GRAVITY_TILES * TILE_SIZE;
    const jumpHeight = JUMP_HEIGHT_TILES * TILE_SIZE;
    this.jumpInitialVelocity = Math.sqrt(2 * gravity * jumpHeight);
    this.physicsDt = 1 / scene.physics.world.fps;

    // Body setup. World gravity (configured in main.ts) handles the
    // gravity arithmetic; allowGravity toggles per state. Bounce 0 so wall
    // contact is a hard stop (the REBOUNDING state authors the visible
    // bounce manually — Phaser bounce would interfere).
    this.body.setBounce(0, 0);
    this.body.setMaxVelocity(this.flightSpeed * 2, this.terminalVelocity);
    this.applyShape(SHAPE_FULL);
  }

  update(_time: number, deltaMs: number): void {
    const dt = deltaMs / 1000;
    if (this.dyingTimer > 0) {
      this.dyingTimer -= dt;
    }
    this.applyShapeForState();
    this.applyGravityForState();
    switch (this.state) {
      case PlayerState.IDLE:          this.idle(dt); break;
      case PlayerState.RISING:        this.rising(dt); break;
      case PlayerState.FLYING_H:      this.flyingH(dt); break;
      case PlayerState.FLYING_UP:     this.flyingUp(dt); break;
      case PlayerState.FLYING_DOWN:   this.flyingDown(dt); break;
      case PlayerState.JUMPING:       this.jumping(dt); break;
      case PlayerState.REBOUNDING:    this.rebounding(dt); break;
      case PlayerState.PAUSED:        this.paused(dt); break;
      case PlayerState.FALLING:       this.falling(dt); break;
      case PlayerState.FALLING_INPUT: this.fallingInput(dt); break;
    }
  }

  // ----- State handlers -----

  private idle(_dt: number): void {
    // x stays zero; engine gravity handles y (presses into floor each
    // frame, collider keeps touching.down / blocked.down set).
    this.body.setVelocityX(0);

    if (!this.isOnFloor()) {
      this.state = PlayerState.FALLING;
      return;
    }

    if (Phaser.Input.Keyboard.JustDown(this.cursors.left)) {
      this.direction = -1;
      this.riseTargetY = this.y - TILE_SIZE;
      this.state = PlayerState.RISING;
    } else if (Phaser.Input.Keyboard.JustDown(this.cursors.right)) {
      this.direction = 1;
      this.riseTargetY = this.y - TILE_SIZE;
      this.state = PlayerState.RISING;
    } else if (Phaser.Input.Keyboard.JustDown(this.cursors.up)) {
      this.body.setVelocity(0, -this.flightSpeed);
      this.state = PlayerState.FLYING_UP;
    } else if (Phaser.Input.Keyboard.JustDown(this.jumpKey)) {
      this.body.setVelocity(0, -this.jumpInitialVelocity);
      this.state = PlayerState.JUMPING;
    }
    // Down on floor: intentionally a no-op in v1, matching Godot.
  }

  private rising(_dt: number): void {
    this.body.setVelocity(0, -this.flightSpeed);
    if (this.isOnCeiling()) {
      // Ceiling clipped the rise. Start horizontal flight from current y.
      this.state = PlayerState.FLYING_H;
    } else if (this.y <= this.riseTargetY) {
      this.y = this.riseTargetY;  // snap to exact tile boundary
      this.state = PlayerState.FLYING_H;
    }
  }

  private flyingH(_dt: number): void {
    this.body.setVelocity(this.direction * this.flightSpeed, 0);
    if ((this.direction > 0 && this.isOnRightWall()) ||
        (this.direction < 0 && this.isOnLeftWall())) {
      this.startRebound();
    }
  }

  private flyingUp(_dt: number): void {
    this.body.setVelocity(0, -this.flightSpeed);
    if (this.isOnCeiling()) {
      this.body.setVelocity(0, 0);
      this.pauseTimer = PAUSE_TIME_SEC;
      this.postPauseState = PlayerState.FALLING_INPUT;
      this.state = PlayerState.PAUSED;
    }
  }

  private flyingDown(_dt: number): void {
    this.body.setVelocity(0, this.flightSpeed);
    if (this.isOnFloor()) {
      this.body.setVelocity(0, 0);
      this.state = PlayerState.IDLE;
    }
  }

  private jumping(_dt: number): void {
    // Engine gravity handles vy; we keep vx at zero unless the player
    // cancels into a horizontal launch. maxVelocity caps the descent at
    // terminal so the arc matches free fall.
    this.body.setVelocityX(0);

    // Mid-jump arrow input cancels the arc and starts a directional launch.
    if (Phaser.Input.Keyboard.JustDown(this.cursors.left)) {
      this.direction = -1;
      this.body.setVelocity(-this.flightSpeed, 0);
      this.state = PlayerState.FLYING_H;
      return;
    }
    if (Phaser.Input.Keyboard.JustDown(this.cursors.right)) {
      this.direction = 1;
      this.body.setVelocity(this.flightSpeed, 0);
      this.state = PlayerState.FLYING_H;
      return;
    }
    if (Phaser.Input.Keyboard.JustDown(this.cursors.up)) {
      this.body.setVelocity(0, -this.flightSpeed);
      this.state = PlayerState.FLYING_UP;
      return;
    }
    if (Phaser.Input.Keyboard.JustDown(this.cursors.down)) {
      this.body.setVelocity(0, this.flightSpeed);
      this.state = PlayerState.FLYING_DOWN;
      return;
    }

    // No directional input — natural arc.
    const vy = this.body.velocity.y;
    if (this.isOnCeiling() && vy < 0) {
      this.body.setVelocity(0, 0);
      this.pauseTimer = PAUSE_TIME_SEC;
      this.postPauseState = PlayerState.FALLING_INPUT;
      this.state = PlayerState.PAUSED;
    } else if (this.isOnFloor() && vy >= 0) {
      this.body.setVelocity(0, 0);
      this.state = PlayerState.IDLE;
    }
  }

  private rebounding(_dt: number): void {
    // Mid-rebound arrow input cancels the bounce-back and launches in the
    // new direction. Pressing toward the wall just hit produces a
    // bounce-bounce hover loop, which is intentional (matches Godot).
    if (Phaser.Input.Keyboard.JustDown(this.cursors.left)) {
      this.direction = -1;
      this.body.setVelocity(-this.flightSpeed, 0);
      this.state = PlayerState.FLYING_H;
      return;
    }
    if (Phaser.Input.Keyboard.JustDown(this.cursors.right)) {
      this.direction = 1;
      this.body.setVelocity(this.flightSpeed, 0);
      this.state = PlayerState.FLYING_H;
      return;
    }
    if (Phaser.Input.Keyboard.JustDown(this.cursors.up)) {
      this.body.setVelocity(0, -this.flightSpeed);
      this.state = PlayerState.FLYING_UP;
      return;
    }
    if (Phaser.Input.Keyboard.JustDown(this.cursors.down)) {
      this.body.setVelocity(0, this.flightSpeed);
      this.state = PlayerState.FLYING_DOWN;
      return;
    }

    // Hit another wall before completing the rebound — stop here.
    if ((this.direction > 0 && this.isOnRightWall()) ||
        (this.direction < 0 && this.isOnLeftWall())) {
      this.endRebound();
      return;
    }

    // Distance still to travel along the rebound direction. Positive =
    // target is ahead of us; zero or negative = at/past target.
    const distRemaining = (this.reboundTargetX - this.x) * this.direction;

    if (distRemaining <= 0) {
      // Already at or past target. Snap (body.reset syncs body +
      // gameObject + zeroes velocity in one call) and end.
      this.body.reset(this.reboundTargetX, this.y);
      this.endRebound();
      return;
    }

    // Look ahead: if a full-speed step would overshoot, slow down so the
    // upcoming physics step lands EXACTLY on target. Uses the physics
    // step's fixed dt (NOT scene render dt) so the math matches what the
    // physics step will actually do, regardless of render frame rate.
    const maxStep = this.flightSpeed * this.physicsDt;
    const speed = distRemaining < maxStep
      ? distRemaining / this.physicsDt
      : this.flightSpeed;
    this.body.setVelocity(this.direction * speed, 0);
  }

  private endRebound(): void {
    this.body.setVelocity(0, 0);
    this.pauseTimer = PAUSE_TIME_SEC;
    this.postPauseState = PlayerState.FALLING_INPUT;
    this.state = PlayerState.PAUSED;
  }

  private paused(dt: number): void {
    this.body.setVelocity(0, 0);
    this.pauseTimer -= dt;
    if (this.pauseTimer <= 0) {
      this.state = this.postPauseState;
      this.postPauseState = PlayerState.FALLING;  // reset for next time
    }
  }

  private falling(_dt: number): void {
    // Engine gravity handles vy (capped at terminal by maxVelocity). We
    // just pin vx at zero so the body falls straight down.
    this.body.setVelocityX(0);
    if (this.isOnFloor()) {
      this.body.setVelocity(0, 0);
      this.state = PlayerState.IDLE;
    }
  }

  private fallingInput(_dt: number): void {
    this.body.setVelocityX(0);

    if (Phaser.Input.Keyboard.JustDown(this.cursors.left)) {
      this.direction = -1;
      this.body.setVelocity(-this.flightSpeed, 0);
      this.state = PlayerState.FLYING_H;
      return;
    }
    if (Phaser.Input.Keyboard.JustDown(this.cursors.right)) {
      this.direction = 1;
      this.body.setVelocity(this.flightSpeed, 0);
      this.state = PlayerState.FLYING_H;
      return;
    }
    if (Phaser.Input.Keyboard.JustDown(this.cursors.up)) {
      this.body.setVelocity(0, -this.flightSpeed);
      this.state = PlayerState.FLYING_UP;
      return;
    }
    if (Phaser.Input.Keyboard.JustDown(this.cursors.down)) {
      this.body.setVelocityY(this.terminalVelocity);
    }

    if (this.isOnFloor()) {
      this.body.setVelocity(0, 0);
      this.state = PlayerState.IDLE;
    }
  }

  // ----- Public API -----

  /** Hazard contact callback. Teleports the body back to spawn, resets
   *  state, and starts a brief immunity window so multiple overlapping
   *  hazard bodies don't fire die() repeatedly on the same death.
   *  No-op while the immunity window is still counting down.
   *  Phase 4 has no death animation; that lands in Phase 6. */
  die(): void {
    if (this.dyingTimer > 0) {
      return;
    }
    this.body.reset(this.spawnPosition.x, this.spawnPosition.y);
    this.state = PlayerState.IDLE;
    this.direction = 0;
    this.pauseTimer = 0;
    this.postPauseState = PlayerState.FALLING;
    this.dyingTimer = DEATH_IMMUNITY_SEC;
  }

  // ----- Helpers -----

  private startRebound(): void {
    this.reboundTargetX = this.x - this.direction * this.reboundDistance;
    this.direction = -this.direction;
    this.state = PlayerState.REBOUNDING;
  }

  // touching.* fires for collisions with other bodies (including static).
  // blocked.* fires for tile / world-bounds collisions. Walls in this
  // scene are static bodies, so touching is the load-bearing check;
  // blocked is included for forward-compat with tilemap-backed walls.
  private isOnFloor(): boolean {
    return this.body.touching.down || this.body.blocked.down;
  }
  private isOnCeiling(): boolean {
    return this.body.touching.up || this.body.blocked.up;
  }
  private isOnLeftWall(): boolean {
    return this.body.touching.left || this.body.blocked.left;
  }
  private isOnRightWall(): boolean {
    return this.body.touching.right || this.body.blocked.right;
  }

  private applyShape(shape: { w: number; h: number }): void {
    if (this.body.width !== shape.w || this.body.height !== shape.h) {
      this.body.setSize(shape.w, shape.h, true);  // re-center on game object
    }
  }

  private applyShapeForState(): void {
    let target: { w: number; h: number };
    switch (this.state) {
      case PlayerState.FLYING_H:
      case PlayerState.REBOUNDING:
        target = SHAPE_HMOVE; break;
      case PlayerState.RISING:
      case PlayerState.FLYING_UP:
      case PlayerState.FLYING_DOWN:
      case PlayerState.JUMPING:
      case PlayerState.FALLING:
      case PlayerState.FALLING_INPUT:
        target = SHAPE_VMOVE; break;
      default:
        target = SHAPE_FULL; break;
    }
    this.applyShape(target);
  }

  private applyGravityForState(): void {
    const useGravity = GRAVITY_STATES.has(this.state);
    if (this.body.allowGravity !== useGravity) {
      this.body.setAllowGravity(useGravity);
    }
  }
}
