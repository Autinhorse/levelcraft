import Phaser from 'phaser';

import {
  TILE_SIZE,
  COLOR_WALL,
  COLOR_SPIKE,
  COLOR_SPIKE_PLATE,
  COLOR_COIN,
  COLOR_GLASS,
  COLOR_CONVEYOR,
  COLOR_TELEPORT,
  COLOR_EXIT,
  COLOR_BACKGROUND,
  COLOR_GRID,
  KEY_COLORS_LIGHT,
  KEY_COLORS_DARK,
  DEFAULT_LEVEL_URL,
  DEFAULT_PAGE_INDEX,
  FADE_DURATION_MS,
} from '../config/feel';
import { Bullet } from '../entities/Bullet';
import { Cannon } from '../entities/Cannon';
import { Gear } from '../entities/Gear';
import { LaserCannon } from '../entities/LaserCannon';
import { CONVEYOR_DIR_DATA_KEY, Player, PlayerState } from '../entities/Player';
import { Portal } from '../entities/Portal';
import { Turret } from '../entities/Turret';
import { validateLevel } from '../../shared/level-format/load';
import type { CardinalDir, LevelData, PageData } from '../../shared/level-format/types';

// Cell-distance pickup struct used for teleport / exit triggers (manual
// distance check, mirroring the no-body coin/key pattern). Half-tile
// AABB threshold so the player only triggers when meaningfully overlapped.
type Trigger = { x: number; y: number; targetPage: number };

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
  // Glass walls: act as walls until the player touches them, then break
  // after their per-instance `delay` (seconds). Separate group so we can
  // attach a per-collision callback that's not run for ordinary walls.
  private glassWalls!: Phaser.Physics.Arcade.StaticGroup;
  // Spike blocks: full-cell elements that BLOCK the player AND kill on
  // contact. Separate group so a single collider+overlap pair can apply
  // both behaviors.
  private killableWalls!: Phaser.Physics.Arcade.StaticGroup;
  // Coins: PURE VISUALS (no physics body) — pickup is checked manually
  // each frame via AABB distance. We deliberately avoid the Phaser
  // physics path because `physics.add.overlap` still sets the player
  // body's `touching.left/right/up/down` flags as a side-effect even
  // though it doesn't separate; FLYING_H reads those flags to detect
  // walls, so a coin in the flight path would falsely trigger a rebound.
  private coins!: Phaser.GameObjects.Group;
  private coinCount = 0;
  // Half the player's body height + half the coin's display size; cached
  // so the pickup loop doesn't recompute it 60 times a second.
  private coinPickupThreshold = 0;
  // Cannons fire on a timer; PlayScene.update ticks each one. Bullets
  // are pooled in `bullets` and despawn on contact with anything.
  private cannons: Cannon[] = [];
  private bullets!: Phaser.GameObjects.Group;
  // Keys: pure visuals (same no-body pattern as coins so flying through
  // them doesn't trip the player's wall-detection). Picking up a key
  // removes ALL key_walls of the matching color on the page.
  private keys!: Phaser.GameObjects.Group;
  private keyPickupThreshold = 0;
  // Key walls: solid wall-like static bodies in their own group, so the
  // pickup-driven removal can iterate JUST the matching-color walls.
  private keyWalls!: Phaser.Physics.Arcade.StaticGroup;
  // Gears tick in PlayScene.update; collisions handled via overlap with
  // the player. Bullets pass through gears (matching Godot — gears are
  // collision_mask=2, player only).
  private gears: Gear[] = [];
  // Portals: paired teleporters. Same "bullets pass through, only player
  // triggers" pattern as gears. Tick ticks the cooldown timers.
  private portals: Portal[] = [];
  // Turrets: like cannons (wall-like, fire on a timer) but the barrel
  // tracks the player. Built before the player exists, so PlayScene
  // calls turret.setPlayer() once player is constructed.
  private turrets: Turret[] = [];
  // Laser cannons: wall-like, with a beam that raycasts each frame and
  // kills the player on segment-vs-AABB overlap. Like turrets, they're
  // added to the walls group so the player + bullets collide with the
  // base cell.
  private laserCannons: LaserCannon[] = [];
  // Spikes / spike-blocks with duration > 0: tracked for the extend /
  // retract cycle. Each entry holds the lethal rect (the only part
  // that toggles — for directional spikes the wall-plate is always-on
  // and lives separately in the walls group). Toggling flips the
  // visual + the static body's `enable` flag so collision and overlap
  // both stop while retracted.
  private timedSpikes: Array<{
    visual: Phaser.GameObjects.Rectangle;
    duration: number;
    downtime: number;
    firing: boolean;
    phaseTimer: number;
  }> = [];
  // Teleports + exit use the no-body distance-trigger pattern so the
  // player passes through them visually without their physics body
  // tripping FLYING_H wall-detection (same trick as coins/keys).
  private teleports: Trigger[] = [];
  private exit: Trigger | null = null;
  // Multi-page state. startPageIndex comes in via init() from
  // scene.restart so a teleport can hand off to the next page; the
  // level itself is parsed once per scene run and cached.
  private startPageIndex = DEFAULT_PAGE_INDEX;
  private currentPageIndex = DEFAULT_PAGE_INDEX;
  private shouldFadeIn = false;
  private loadedLevel!: LevelData;
  // Set when init() receives an in-memory level (the editor's "Play"
  // hand-off). Non-null means: skip preload's file fetch and use the
  // provided level; restarts (cross-page teleports) re-pass it through
  // scene.restart so it survives across page transitions.
  private providedLevel: LevelData | null = null;
  // True iff PlayScene was launched from EditScene — surfaces a "Back
  // to Editor" button so the user can hop back without a refresh.
  private launchedFromEditor = false;
  // Disk path of the level being played, when launched from the editor.
  // Passed back to EditScene on the "back" round-trip so its Save
  // button still knows which file to write to.
  private levelPath: string | null = null;
  // Black overlay for transition fade-out / fade-in. Pinned to the
  // camera (scrollFactor 0) so it covers the whole viewport regardless
  // of the centered-room camera scroll.
  private fadeOverlay!: Phaser.GameObjects.Rectangle;
  private transitioning = false;
  private debugText!: Phaser.GameObjects.Text;
  private hudText!: Phaser.GameObjects.Text;
  // DOM "Back to Editor" button — only shown when launched from EditScene.
  private backButton: HTMLDivElement | null = null;

  constructor() {
    super('PlayScene');
  }

  // Receives data from scene.restart on cross-page transitions and from
  // EditScene's "Play" hand-off. First boot has no data, so falls back to
  // DEFAULT_PAGE_INDEX with no fade-in (instant initial render).
  init(data?: {
    pageIndex?: number;
    fadeIn?: boolean;
    level?: LevelData;
    fromEditor?: boolean;
    levelPath?: string;
  }): void {
    this.startPageIndex = data?.pageIndex ?? DEFAULT_PAGE_INDEX;
    this.shouldFadeIn = data?.fadeIn ?? false;
    this.providedLevel = data?.level ?? null;
    // Sticky: once launched from the editor, in-game page transitions
    // preserve the flag (restart-through-transitionToPage re-passes it).
    this.launchedFromEditor = data?.fromEditor ?? false;
    this.levelPath = data?.levelPath ?? null;
  }

  preload(): void {
    // Skip the file fetch when an in-memory level was handed to us —
    // the editor's level may be unsaved and not yet on disk.
    if (!this.providedLevel) {
      this.load.json(LEVEL_KEY, DEFAULT_LEVEL_URL);
    }
  }

  create(): void {
    this.cameras.main.setBackgroundColor(COLOR_BACKGROUND);

    const raw = (this.providedLevel ?? this.cache.json.get(LEVEL_KEY)) as unknown;
    this.loadedLevel = validateLevel(raw, DEFAULT_LEVEL_URL);
    this.currentPageIndex = this.startPageIndex;
    const page = this.loadedLevel.pages[this.currentPageIndex];
    if (!page) {
      throw new Error(`Level has no page index ${this.currentPageIndex}`);
    }
    this.transitioning = false;

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
    this.glassWalls = this.physics.add.staticGroup();
    this.killableWalls = this.physics.add.staticGroup();
    this.coins = this.add.group();  // plain group — no physics, see field comment
    this.coinCount = 0;
    this.bullets = this.add.group();
    this.cannons = [];
    this.keys = this.add.group();
    this.keyWalls = this.physics.add.staticGroup();
    this.gears = [];
    this.portals = [];
    this.turrets = [];
    this.laserCannons = [];
    this.timedSpikes = [];
    this.teleports = [];
    this.exit = null;
    this.buildWalls(page);
    this.buildSpikes(page);
    this.buildGlassWalls(page);
    this.buildSpikeBlocks(page);
    this.buildConveyors(page);
    this.buildCannons(page);
    this.buildKeyWalls(page);
    this.buildKeys(page);
    this.buildGears(page);
    this.buildPortals(page);
    this.buildTurrets(page);
    this.buildLaserCannons(page);
    this.buildTextLabels(page);
    this.buildTeleports(page);
    this.buildExit();

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
    // Turrets are built before the player; hand them the player ref now
    // so trackPlayer() can read its position each frame.
    for (const turret of this.turrets) {
      turret.setPlayer(this.player);
    }

    this.physics.add.collider(this.player, this.walls);
    this.physics.add.overlap(this.player, this.hazards, () => this.player.die());
    // Glass walls: collide normally; the callback starts the break timer
    // on first contact and ignores subsequent contacts until the wall
    // self-destructs.
    this.physics.add.collider(this.player, this.glassWalls, (_player, glass) => {
      this.triggerGlassWall(glass as Phaser.GameObjects.GameObject);
    });
    // Spike blocks: collide (player physically stops) AND overlap (player
    // dies). Both fire on contact; the death animation's collision-off
    // takes care of the body separating cleanly afterward.
    this.physics.add.collider(this.player, this.killableWalls);
    this.physics.add.overlap(this.player, this.killableWalls, () => this.player.die());
    // (Coin pickup is handled manually in update() via distance check —
    // see the field comment on `coins`.) Pre-compute the AABB threshold:
    // half player width (TILE_SIZE/2) plus half coin width (0.55 * TILE_SIZE / 2).
    this.coinPickupThreshold = TILE_SIZE * 0.5 + TILE_SIZE * 0.275;
    // Same trick for keys (radius 0.25 tile, so threshold = 0.5 + 0.25).
    this.keyPickupThreshold = TILE_SIZE * 0.5 + TILE_SIZE * 0.25;
    // Key walls are walls — block the player. Bullet despawn against
    // them is added below alongside the other wall-like groups.
    this.physics.add.collider(this.player, this.keyWalls);

    // Bullets despawn on contact with anything wall-like. The same callback
    // handles all wall-like groups; the per-bullet `ignoreBody`/`ignoreTimer`
    // pattern lets future shooters (turrets) exempt themselves at oblique
    // firing angles. Cannons fire perpendicular so they never set ignoreBody.
    const handleBulletWallHit: Phaser.Types.Physics.Arcade.ArcadePhysicsCallback = (bullet, wall) => {
      const b = bullet as unknown as Bullet;
      if (!b.active) return;  // already destroyed (multi-overlap same frame)
      if (b.ignoreBody === (wall as unknown as Phaser.GameObjects.GameObject) && b.ignoreTimer > 0) return;
      b.destroy();
    };
    this.physics.add.overlap(this.bullets, this.walls, handleBulletWallHit);
    this.physics.add.overlap(this.bullets, this.glassWalls, handleBulletWallHit);
    this.physics.add.overlap(this.bullets, this.killableWalls, handleBulletWallHit);
    this.physics.add.overlap(this.bullets, this.hazards, handleBulletWallHit);
    this.physics.add.overlap(this.bullets, this.keyWalls, handleBulletWallHit);
    // Bullet vs player: kill + despawn.
    this.physics.add.overlap(this.player, this.bullets, (_player, bullet) => {
      this.player.die();
      bullet.destroy();
    });
    // Player vs gears (overlap kills). Gears are intentionally NOT in
    // the bullet wall-hit handler — bullets pass through them, mirroring
    // the Godot collision_mask=2 (player only) configuration.
    this.physics.add.overlap(this.player, this.gears, () => this.player.die());
    // Portals: same "player only" pattern. The portal's own callback
    // does the teleport + cooldown.
    this.physics.add.overlap(this.player, this.portals, (_player, portal) => {
      (portal as Portal).handlePlayerOverlap(this.player);
    });

    // HUD — anchored to the screen, not the world, so it doesn't move
    // when the camera scrolls (setScrollFactor(0) is the standard idiom).
    this.add
      .text(
        16,
        this.scale.gameSize.height - 28,
        `${this.loadedLevel.name}  (page ${this.currentPageIndex + 1}/${this.loadedLevel.pages.length})  |  Arrows: launch  |  Space: jump`,
        { color: '#9aa0a8', fontSize: '14px' },
      )
      .setScrollFactor(0);

    // Coin counter — top-right.
    this.hudText = this.add
      .text(this.scale.gameSize.width - 16, 16, '', {
        color: '#ffd933',
        fontSize: '20px',
        fontFamily: 'monospace',
      })
      .setOrigin(1, 0)
      .setScrollFactor(0);

    this.debugText = this.add
      .text(16, 16, '', {
        color: '#cccccc',
        fontSize: '14px',
        fontFamily: 'monospace',
      })
      .setScrollFactor(0);

    // Fade overlay (full design viewport, scroll-locked, on top of
    // everything). Starts opaque on a transition entrance so the player
    // sees a clean fade-in; instant-render on the very first scene boot.
    this.fadeOverlay = this.add
      .rectangle(0, 0, this.scale.gameSize.width, this.scale.gameSize.height, 0x000000)
      .setOrigin(0, 0)
      .setScrollFactor(0)
      .setDepth(1000)
      .setAlpha(this.shouldFadeIn ? 1 : 0);
    if (this.shouldFadeIn) {
      this.tweens.add({
        targets: this.fadeOverlay,
        alpha: 0,
        duration: FADE_DURATION_MS,
      });
    }

    if (this.launchedFromEditor) {
      this.buildBackButton();
    }
    // Tear down DOM additions on shutdown so they don't linger after a
    // scene switch (back to editor) or hot reload.
    this.events.once(Phaser.Scenes.Events.SHUTDOWN, () => this.destroyBackButton());
    this.events.once(Phaser.Scenes.Events.DESTROY, () => this.destroyBackButton());
  }

  private buildBackButton(): void {
    if (this.backButton) return;
    const wrap = document.createElement('div');
    wrap.className = 'editor-overlay';
    wrap.innerHTML = `
      <div class="editor-back-wrap">
        <button class="editor-btn">◀ Edit</button>
      </div>
    `;
    document.body.appendChild(wrap);
    this.backButton = wrap;
    wrap.querySelector('button')?.addEventListener('click', () => {
      this.scene.start('EditScene', {
        level: this.providedLevel ?? this.loadedLevel,
        pageIndex: this.currentPageIndex,
        levelPath: this.levelPath ?? undefined,
      });
    });
  }

  private destroyBackButton(): void {
    if (this.backButton) {
      this.backButton.remove();
      this.backButton = null;
    }
  }

  update(time: number, delta: number): void {
    this.player.update(time, delta);
    this.checkCoinPickups();
    this.checkKeyPickups();
    this.checkPageTriggers();

    const dt = delta / 1000;
    for (const cannon of this.cannons) {
      cannon.tick(dt);
    }
    for (const gear of this.gears) {
      gear.tick(dt);
    }
    for (const portal of this.portals) {
      portal.tick(dt);
    }
    for (const turret of this.turrets) {
      turret.tick(dt);
    }
    for (const laser of this.laserCannons) {
      laser.tick(dt);
      // Beam-vs-player kill: arcade physics has no rotated-body support,
      // so the laser does its own segment-vs-AABB test. One break is
      // enough — die() is idempotent on already-dead state.
      if (laser.checkPlayerHit(this.player)) {
        this.player.die();
      }
    }
    // Timed spikes: extend / retract cycle. Only the lethal rect
    // toggles. For spike_blocks, the small central plate stays in
    // `walls` permanently — it provides the "small cube blocks the
    // player when retracted" behavior without any per-frame body
    // bookkeeping. While the spike is extended, the player dies on
    // contact and `die()` clears checkCollision, so the dying body
    // passes the plate harmlessly.
    for (const ts of this.timedSpikes) {
      ts.phaseTimer -= dt;
      if (ts.phaseTimer <= 0) {
        ts.firing = !ts.firing;
        ts.phaseTimer = ts.firing ? ts.duration : ts.downtime;
        ts.visual.setVisible(ts.firing);
        const body = ts.visual.body as Phaser.Physics.Arcade.StaticBody;
        body.enable = ts.firing;
      }
    }
    // Tick all live bullets (decrements ignoreTimer + lifetime).
    this.bullets.getChildren().forEach((b) => {
      const bullet = b as Bullet;
      if (bullet.active) bullet.tick(dt);
    });

    const t = this.player.body.touching;
    const b = this.player.body.blocked;
    this.debugText.setText([
      `state: ${PlayerState[this.player.state]}`,
      `vel: (${this.player.body.velocity.x.toFixed(0)}, ${this.player.body.velocity.y.toFixed(0)})`,
      `touching: ${t.up ? 'U' : '-'}${t.down ? 'D' : '-'}${t.left ? 'L' : '-'}${t.right ? 'R' : '-'}`,
      `blocked:  ${b.up ? 'U' : '-'}${b.down ? 'D' : '-'}${b.left ? 'L' : '-'}${b.right ? 'R' : '-'}`,
    ]);
    this.hudText.setText(`coins: ${this.coinCount}`);
  }

  private buildWalls(page: PageData): void {
    // Tile-grid pass: 'W' = wall, 'C' = coin, '.' = empty. Other chars are
    // ignored (forward-compat for future tile-char additions).
    for (let r = 0; r < page.tiles.length; r++) {
      const row = page.tiles[r]!;
      for (let c = 0; c < row.length; c++) {
        const ch = row.charAt(c);
        if (ch === 'W') {
          this.makeWall(c, r);
        } else if (ch === 'C') {
          this.makeCoin(c, r);
        }
      }
    }
  }

  private makeCoin(col: number, row: number): void {
    const x = (col + 0.5) * TILE_SIZE;
    const y = (row + 0.5) * TILE_SIZE;
    // Smaller than a tile so the coin reads as a pickup, not a tile.
    // No physics body — pickup is handled by checkCoinPickups() below.
    const size = TILE_SIZE * 0.55;
    const visual = this.add.rectangle(x, y, size, size, COLOR_COIN);
    this.coins.add(visual);
  }

  // AABB-style pickup check. The player's body width is roughly TILE_SIZE
  // (the per-state shape narrows by 2-4px on the perpendicular axis;
  // ignoring those few pixels here doesn't matter for pickup feel).
  private checkCoinPickups(): void {
    const px = this.player.x;
    const py = this.player.y;
    const t = this.coinPickupThreshold;
    const children = this.coins.getChildren();
    // Iterate backwards so destroying mid-loop doesn't skip elements.
    for (let i = children.length - 1; i >= 0; i--) {
      const coin = children[i] as Phaser.GameObjects.Rectangle;
      if (Math.abs(coin.x - px) < t && Math.abs(coin.y - py) < t) {
        coin.destroy();
        this.coinCount += 1;
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
      const lethalRect = this.makeSpike(spike.x, spike.y, spike.dir);
      this.maybeRegisterTimedSpike(lethalRect, spike.duration, spike.downtime);
    }
  }

  private makeSpike(col: number, row: number, dir: CardinalDir): Phaser.GameObjects.Rectangle {
    const layout = SPIKE_LAYOUT[dir];
    // Plate first (visually beneath the spike where they overlap), spike on top.
    this.makeSpikePart(col, row, layout.plate, COLOR_SPIKE_PLATE, /* hazard= */ false);
    return this.makeSpikePart(col, row, layout.spike, COLOR_SPIKE, /* hazard= */ true);
  }

  private makeSpikePart(
    col: number,
    row: number,
    rect: Rect,
    color: number,
    hazard: boolean,
  ): Phaser.GameObjects.Rectangle {
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
    return visual;
  }

  // Adds the rect to the timed-spike list IFF duration > 0. Static
  // (always-extended) spikes are skipped — no toggle work needed each
  // frame, matching the legacy zero-overhead behavior.
  private maybeRegisterTimedSpike(
    visual: Phaser.GameObjects.Rectangle,
    duration: number | undefined,
    downtime: number | undefined,
  ): void {
    const dur = duration ?? 0;
    if (dur <= 0) return;
    const down = downtime ?? 3.0;
    this.timedSpikes.push({
      visual,
      duration: dur,
      downtime: down,
      firing: true,
      phaseTimer: dur,
    });
  }

  private buildGlassWalls(page: PageData): void {
    if (!page.glass_walls) {
      return;
    }
    for (const gw of page.glass_walls) {
      this.makeGlassWall(gw.x, gw.y, gw.delay);
    }
  }

  private makeGlassWall(col: number, row: number, delay: number): void {
    const x = (col + 0.5) * TILE_SIZE;
    const y = (row + 0.5) * TILE_SIZE;
    const visual = this.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_GLASS);
    visual.setAlpha(0.55);  // semi-transparent for the "glass" look
    this.glassWalls.add(visual);
    visual.setData('delay', delay);
    visual.setData('triggered', false);
    const body = visual.body as Phaser.Physics.Arcade.StaticBody;
    body.setSize(TILE_SIZE, TILE_SIZE);
    body.updateFromGameObject();
  }

  // First player contact starts the break timer for the WHOLE connected
  // shatter group: 4-adjacent glass walls flood-filled from the touched
  // cell. Reads physically as "this row/pane of glass is one barrier and
  // it's all cracked" instead of "pop, pop, pop" as the player traverses
  // each cell. Already-triggered members are skipped so neighbouring
  // groups touched in the same frame don't double-schedule.
  private triggerGlassWall(glass: Phaser.GameObjects.GameObject): void {
    if (glass.getData('triggered')) {
      return;
    }
    const group = this.findGlassGroup(glass as Phaser.GameObjects.Rectangle);
    for (const member of group) {
      if (member.getData('triggered')) continue;
      member.setData('triggered', true);
      const delaySec = (member.getData('delay') as number) ?? 1.0;
      this.time.delayedCall(delaySec * 1000, () => member.destroy());
    }
  }

  // BFS over 4-adjacent glass-wall cells starting from `start`. Cell key
  // is `col,row` derived from each rect's center position (each wall is
  // 1×1 tile, axis-aligned, so floor(x/TILE) gives the column).
  private findGlassGroup(
    start: Phaser.GameObjects.Rectangle,
  ): Phaser.GameObjects.Rectangle[] {
    const cellMap = new Map<string, Phaser.GameObjects.Rectangle>();
    for (const obj of this.glassWalls.getChildren()) {
      const gw = obj as Phaser.GameObjects.Rectangle;
      const col = Math.floor(gw.x / TILE_SIZE);
      const row = Math.floor(gw.y / TILE_SIZE);
      cellMap.set(`${col},${row}`, gw);
    }
    const result: Phaser.GameObjects.Rectangle[] = [];
    const visited = new Set<string>();
    const queue: { col: number; row: number }[] = [
      { col: Math.floor(start.x / TILE_SIZE), row: Math.floor(start.y / TILE_SIZE) },
    ];
    while (queue.length > 0) {
      const { col, row } = queue.shift()!;
      const key = `${col},${row}`;
      if (visited.has(key)) continue;
      visited.add(key);
      const gw = cellMap.get(key);
      if (!gw) continue;
      result.push(gw);
      queue.push({ col: col + 1, row });
      queue.push({ col: col - 1, row });
      queue.push({ col, row: row + 1 });
      queue.push({ col, row: row - 1 });
    }
    return result;
  }

  private buildSpikeBlocks(page: PageData): void {
    if (!page.spike_blocks) {
      return;
    }
    for (const sb of page.spike_blocks) {
      const spike = this.makeSpikeBlock(sb.x, sb.y);
      this.maybeRegisterTimedSpike(spike, sb.duration, sb.downtime);
    }
  }

  // Spike block is two independent bodies:
  //   spike — full-cell rect in `hazards` (overlap-kills, no collider).
  //           When extended, the player walks in and dies on contact;
  //           there's no physical block, just lethal contact.
  //           Toggled by the timer (visible+enabled while extended).
  //   plate — small central cube in `walls` (collider, no kill).
  //           ALWAYS active. While the spike is extended, the player
  //           dies before reaching the plate (and `die()` disables
  //           body collision so the dying body passes through it).
  //           While the spike is retracted, the plate is the only
  //           obstacle in the cell — the small cube blocks the player.
  // Always-on plate avoids the one-frame race that toggling caused
  // (player flying past during the body re-enable propagation).
  private makeSpikeBlock(col: number, row: number): Phaser.GameObjects.Rectangle {
    const x = (col + 0.5) * TILE_SIZE;
    const y = (row + 0.5) * TILE_SIZE;

    const spike = this.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_SPIKE);
    this.hazards.add(spike);
    const spikeBody = spike.body as Phaser.Physics.Arcade.StaticBody;
    spikeBody.setSize(TILE_SIZE, TILE_SIZE);
    spikeBody.updateFromGameObject();

    // Plate width is intentionally 2/3 tile rather than 1/3. Phaser's
    // ProcessX.Set (in node_modules/phaser/src/physics/arcade/) picks
    // separation direction by shortest-distance, NOT by velocity. When
    // a fast-moving player overshoots more than halfway through a
    // small static body in one frame, the shorter exit is forward —
    // Phaser pushes the player out the far side, "tunneling" them
    // through the cube. Math: to keep `body1OnLeft = false` for a
    // player width 48 moving 32 px/frame, plate width must be > 16.
    // 2/3 tile = 32 px gives comfortable margin even with mild FPS dips.
    const plateSize = TILE_SIZE * 2 / 3;
    const plate = this.add.rectangle(x, y, plateSize, plateSize, COLOR_SPIKE_PLATE);
    this.walls.add(plate);
    const plateBody = plate.body as Phaser.Physics.Arcade.StaticBody;
    plateBody.setSize(plateSize, plateSize);
    plateBody.updateFromGameObject();

    return spike;
  }

  private buildConveyors(page: PageData): void {
    if (!page.conveyors) {
      return;
    }
    for (const cv of page.conveyors) {
      this.makeConveyor(cv.x, cv.y, cv.dir === 'cw' ? 1 : -1);
    }
  }

  // Conveyor: a wall-like static body (so the player can stand on it
  // and it blocks horizontal flight) with a `conveyorDir` data tag the
  // player's idle probe reads to apply horizontal push. Lives in the
  // walls group so the existing player↔walls collider handles it.
  private makeConveyor(col: number, row: number, dir: 1 | -1): void {
    const x = (col + 0.5) * TILE_SIZE;
    const y = (row + 0.5) * TILE_SIZE;
    const visual = this.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_CONVEYOR);
    this.walls.add(visual);
    visual.setData(CONVEYOR_DIR_DATA_KEY, dir);
    const body = visual.body as Phaser.Physics.Arcade.StaticBody;
    body.setSize(TILE_SIZE, TILE_SIZE);
    body.updateFromGameObject();

    // Direction arrow (visual only). Makes the push direction obvious
    // at a glance.
    this.add
      .text(x, y, dir === 1 ? '→' : '←', {
        color: '#ffffff',
        fontSize: '24px',
        fontStyle: 'bold',
      })
      .setOrigin(0.5);
  }

  private buildCannons(page: PageData): void {
    if (!page.cannons) {
      return;
    }
    for (const c of page.cannons) {
      const cannon = new Cannon(
        this,
        c.x,
        c.y,
        c.dir,
        c.period,
        c.bullet_speed,
        this.bullets,
      );
      // Add to the walls group so the existing player↔walls collider
      // physically blocks the player against the cannon's cell.
      this.walls.add(cannon);
      this.cannons.push(cannon);
    }
  }

  private buildKeys(page: PageData): void {
    if (!page.keys) {
      return;
    }
    for (const k of page.keys) {
      this.makeKey(k.x, k.y, k.color);
    }
  }

  // No physics body — same pattern as coins (a body would set the
  // player's `touching.X` flags as a side-effect and trip FLYING_H's
  // wall-detection). Pickup is a manual distance check in update().
  private makeKey(col: number, row: number, colorIdx: number): void {
    const x = (col + 0.5) * TILE_SIZE;
    const y = (row + 0.5) * TILE_SIZE;
    const radius = TILE_SIZE * 0.25;
    const palette = KEY_COLORS_LIGHT[colorIdx] ?? 0xffffff;
    const visual = this.add.circle(x, y, radius, palette);
    visual.setData('color', colorIdx);
    this.keys.add(visual);
  }

  private buildKeyWalls(page: PageData): void {
    if (!page.key_walls) {
      return;
    }
    for (const kw of page.key_walls) {
      this.makeKeyWall(kw.x, kw.y, kw.color);
    }
  }

  // Solid wall — player can't pass; bullet hits despawn it. Same group
  // shape as `walls`/`glassWalls`, just kept separate so picking up a
  // matching-color key only iterates these and not every wall on the page.
  private makeKeyWall(col: number, row: number, colorIdx: number): void {
    const x = (col + 0.5) * TILE_SIZE;
    const y = (row + 0.5) * TILE_SIZE;
    const palette = KEY_COLORS_DARK[colorIdx] ?? 0x444444;
    const visual = this.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, palette);
    visual.setData('color', colorIdx);
    this.keyWalls.add(visual);
    const body = visual.body as Phaser.Physics.Arcade.StaticBody;
    body.setSize(TILE_SIZE, TILE_SIZE);
    body.updateFromGameObject();
  }

  private checkKeyPickups(): void {
    const px = this.player.x;
    const py = this.player.y;
    const t = this.keyPickupThreshold;
    const children = this.keys.getChildren();
    for (let i = children.length - 1; i >= 0; i--) {
      const key = children[i] as Phaser.GameObjects.Arc;
      if (Math.abs(key.x - px) < t && Math.abs(key.y - py) < t) {
        const colorIdx = key.getData('color') as number;
        key.destroy();
        this.removeKeyWallsByColor(colorIdx);
      }
    }
  }

  // Cascade: collecting a key destroys ALL key_walls that share its color.
  private removeKeyWallsByColor(colorIdx: number): void {
    const walls = this.keyWalls.getChildren();
    // Iterate backwards because destroy() removes from the group's list.
    for (let i = walls.length - 1; i >= 0; i--) {
      const wall = walls[i] as Phaser.GameObjects.Rectangle;
      if (wall.getData('color') === colorIdx) {
        wall.destroy();
      }
    }
  }

  private buildTurrets(page: PageData): void {
    if (!page.turrets) {
      return;
    }
    for (const t of page.turrets) {
      const turret = new Turret(
        this,
        t.x,
        t.y,
        t.period,
        t.bullet_speed,
        this.bullets,
      );
      // Add to walls group so the player + bullets collide with the
      // turret's cell exactly like with a cannon.
      this.walls.add(turret);
      this.turrets.push(turret);
    }
  }

  // Beam-blocker check shared by every laser cannon on this page.
  // Queries live state — glass walls broken mid-play / key walls
  // removed after pickup stop blocking once they're gone. Out-of-
  // bounds counts as blocking so the beam terminates at the level
  // edge instead of running for full max-range.
  private isLaserBlocker = (col: number, row: number): boolean => {
    const page = this.loadedLevel.pages[this.currentPageIndex];
    if (!page) return true;
    if (row < 0 || col < 0) return true;
    if (row >= page.tiles.length) return true;
    if (col >= page.tiles[0]!.length) return true;
    // walls group covers regular walls + cannons + turrets + laser
    // cannons themselves (they're all added to walls). The other three
    // groups are checked individually because they're separate.
    const cx = (col + 0.5) * TILE_SIZE;
    const cy = (row + 0.5) * TILE_SIZE;
    const groupHasCell = (group: Phaser.Physics.Arcade.StaticGroup): boolean =>
      group.getChildren().some((child) => {
        const obj = child as Phaser.GameObjects.GameObject & { x?: number; y?: number };
        return obj.x === cx && obj.y === cy;
      });
    return (
      groupHasCell(this.walls) ||
      groupHasCell(this.glassWalls) ||
      groupHasCell(this.killableWalls) ||
      groupHasCell(this.keyWalls) ||
      // Hazards include the spike_block's full-cell lethal rect (centered
      // on the cell, so groupHasCell matches). Directional spikes also
      // live in hazards but their rects are off-center per SPIKE_LAYOUT,
      // so the cx/cy equality test naturally excludes them — the laser
      // passes over a directional spike's cell, only stopping at solids.
      groupHasCell(this.hazards)
    );
  };

  private buildLaserCannons(page: PageData): void {
    if (!page.laser_cannons) {
      return;
    }
    for (const lc of page.laser_cannons) {
      const laser = new LaserCannon(
        this,
        lc.x,
        lc.y,
        lc.dir,
        lc.rotate,
        lc.duration,
        lc.downtime,
        this.isLaserBlocker,
        this.gears,
      );
      this.walls.add(laser);
      this.laserCannons.push(laser);
    }
  }

  private buildPortals(page: PageData): void {
    if (!page.portals) {
      return;
    }
    for (const pair of page.portals) {
      const built: Portal[] = [];
      for (const point of pair.points) {
        const portal = new Portal(this, point.x, point.y, pair.color);
        built.push(portal);
        this.portals.push(portal);
      }
      // Pair completion — only fully-formed (2-point) pairs are
      // functional; orphan singletons stay non-teleporting (partner null).
      if (built.length === 2) {
        built[0]!.partner = built[1]!;
        built[1]!.partner = built[0]!;
      }
    }
  }

  private buildGears(page: PageData): void {
    if (!page.gears) {
      return;
    }
    for (const g of page.gears) {
      const radiusPx = (g.size * TILE_SIZE) / 2;
      const speedPx = g.speed * TILE_SIZE;
      // Build the path in pixel coords. Index 0 is home, then each
      // waypoint cell-center.
      const path: Phaser.Math.Vector2[] = [
        new Phaser.Math.Vector2((g.x + 0.5) * TILE_SIZE, (g.y + 0.5) * TILE_SIZE),
      ];
      for (const wp of g.waypoints) {
        path.push(new Phaser.Math.Vector2((wp.x + 0.5) * TILE_SIZE, (wp.y + 0.5) * TILE_SIZE));
      }
      const gear = new Gear(
        this,
        path[0]!.x,
        path[0]!.y,
        radiusPx,
        speedPx,
        g.spin,
        path,
        g.closed,
      );
      this.gears.push(gear);
    }
  }

  // Decorative multi-cell text overlays. No body, no interaction —
  // pure visual. The cell-bounds outline drawn by the editor is
  // dropped at runtime; only the typed copy renders.
  private buildTextLabels(page: PageData): void {
    if (!page.text_labels) {
      return;
    }
    const pad = 4;
    for (const tl of page.text_labels) {
      if (tl.text.length === 0) continue;
      this.add.text(
        tl.x * TILE_SIZE + pad,
        tl.y * TILE_SIZE + pad,
        tl.text,
        {
          color: '#cccccc',
          fontSize: '16px',
          fontFamily: 'system-ui, -apple-system, sans-serif',
          wordWrap: { width: tl.width * TILE_SIZE - pad * 2 },
        },
      );
    }
  }

  private buildTeleports(page: PageData): void {
    if (!page.teleports) {
      return;
    }
    for (const tp of page.teleports) {
      const x = (tp.x + 0.5) * TILE_SIZE;
      const y = (tp.y + 0.5) * TILE_SIZE;
      // No body — manual distance trigger in checkPageTriggers. The
      // visual is a cell-sized orange rect with a "→N" label showing
      // the destination page (1-indexed for human readability).
      this.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_TELEPORT);
      this.add
        .text(x, y, `→${tp.target_page + 1}`, {
          color: '#000000',
          fontSize: '20px',
          fontStyle: 'bold',
        })
        .setOrigin(0.5);
      this.teleports.push({ x, y, targetPage: tp.target_page });
    }
  }

  // The level's exit is a single point; only renders if it's on this
  // page. Reaching it currently transitions back to page 0 (i.e.
  // restart the level); a future phase swaps that for a proper
  // "level complete" UX.
  private buildExit(): void {
    const exit = this.loadedLevel.exit;
    if (!exit || exit.page !== this.currentPageIndex) {
      return;
    }
    const x = (exit.x + 0.5) * TILE_SIZE;
    const y = (exit.y + 0.5) * TILE_SIZE;
    this.add.rectangle(x, y, TILE_SIZE, TILE_SIZE, COLOR_EXIT);
    this.add
      .text(x, y, 'EXIT', {
        color: '#000000',
        fontSize: '14px',
        fontStyle: 'bold',
      })
      .setOrigin(0.5);
    this.exit = { x, y, targetPage: 0 };
  }

  // AABB-style trigger check for teleports + exit (same pattern as
  // coins / keys). No-op while a transition is already in progress so
  // a single touch can't queue multiple page jumps.
  //
  // Two thresholds, intentionally different:
  //   - Teleports: half-tile (player CENTER must be inside the cell).
  //     Teleports are mid-air navigation; near-miss triggers would
  //     teleport the player against their intent.
  //   - Exit: full-tile (player BODY must overlap the cell). The player
  //     is deliberately seeking the exit, so a 24-px dead zone on each
  //     side of the cell — where the player visually overlaps but the
  //     center-only check still fails — was just frustration.
  private checkPageTriggers(): void {
    if (this.transitioning) {
      return;
    }
    const px = this.player.x;
    const py = this.player.y;
    const teleportT = TILE_SIZE * 0.5;
    for (const tp of this.teleports) {
      if (Math.abs(tp.x - px) < teleportT && Math.abs(tp.y - py) < teleportT) {
        this.transitionToPage(tp.targetPage);
        return;
      }
    }
    const exitT = TILE_SIZE;
    if (this.exit && Math.abs(this.exit.x - px) < exitT && Math.abs(this.exit.y - py) < exitT) {
      this.handleExit();
    }
  }

  // End-of-level handler. Editor-launched runs return to EditScene on
  // the exit page (so the user can keep iterating). Standalone runs fade
  // to a "LEVEL COMPLETE" screen with a click-to-restart prompt — a
  // proper end-of-level UX is a future phase.
  private handleExit(): void {
    if (this.transitioning) return;
    this.transitioning = true;
    this.tweens.add({
      targets: this.fadeOverlay,
      alpha: 1,
      duration: FADE_DURATION_MS,
      onComplete: () => {
        if (this.launchedFromEditor) {
          this.scene.start('EditScene', {
            level: this.providedLevel ?? this.loadedLevel,
            pageIndex: this.loadedLevel.exit.page,
            levelPath: this.levelPath ?? undefined,
          });
        } else {
          this.showLevelComplete();
        }
      },
    });
  }

  private showLevelComplete(): void {
    this.add
      .text(
        this.scale.gameSize.width / 2,
        this.scale.gameSize.height / 2 - 24,
        'LEVEL COMPLETE',
        {
          color: '#66d973',
          fontSize: '64px',
          fontStyle: 'bold',
          fontFamily: 'system-ui, sans-serif',
        },
      )
      .setOrigin(0.5)
      .setScrollFactor(0)
      .setDepth(1001);
    this.add
      .text(
        this.scale.gameSize.width / 2,
        this.scale.gameSize.height / 2 + 36,
        'Click anywhere to restart',
        {
          color: '#cccccc',
          fontSize: '20px',
          fontFamily: 'system-ui, sans-serif',
        },
      )
      .setOrigin(0.5)
      .setScrollFactor(0)
      .setDepth(1001);
    this.input.once('pointerdown', () => {
      this.scene.restart({ pageIndex: 0 });
    });
  }

  // Cross-page transition. Fades to black, then scene.restart with the
  // target page index — restart re-runs init/preload/create cleanly,
  // tearing down all entities for free. The new scene fades in via the
  // shouldFadeIn flag we pass through init data. If the level was
  // provided in-memory (editor hand-off), re-pass it so it survives the
  // restart instead of falling back to the on-disk file.
  private transitionToPage(targetPage: number): void {
    if (
      targetPage < 0 ||
      targetPage >= this.loadedLevel.pages.length ||
      this.transitioning
    ) {
      return;
    }
    this.transitioning = true;
    this.tweens.add({
      targets: this.fadeOverlay,
      alpha: 1,
      duration: FADE_DURATION_MS,
      onComplete: () => {
        const restartData: {
          pageIndex: number;
          fadeIn: boolean;
          level?: LevelData;
          fromEditor?: boolean;
          levelPath?: string;
        } = { pageIndex: targetPage, fadeIn: true };
        if (this.providedLevel) restartData.level = this.providedLevel;
        if (this.launchedFromEditor) restartData.fromEditor = true;
        if (this.levelPath) restartData.levelPath = this.levelPath;
        this.scene.restart(restartData);
      },
    });
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
