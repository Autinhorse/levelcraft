// Game-feel tuning constants. Single source of truth so playtesting can
// dial in numbers in one file. Mirrors the Godot version's
// player_tuning.json so the port preserves identical mechanic feel; tweak
// here, not scattered across the codebase.

// ----- World geometry -----

export const TILE_SIZE = 48;

// (Room dimensions and spawn position were here in Phase 2; they're now
// per-level data, read from the level JSON by the level loader.)

// Default level to load on game boot. Will become user-selectable once
// the level browser exists.
export const DEFAULT_LEVEL_URL = 'levels/test.json';
export const DEFAULT_PAGE_INDEX = 0;

// ----- Player tuning (in tiles; converted to px in Player.ts via TILE_SIZE) -----

export const FLIGHT_SPEED_TILES = 40.0;       // every directed launch
export const GRAVITY_TILES = 40.0;            // tiles/sec^2
export const TERMINAL_VELOCITY_TILES = 40.0;  // fall-speed cap, tiles/sec
export const JUMP_HEIGHT_TILES = 2.0;         // peak above the floor
export const REBOUND_DISTANCE_TILES = 0.2;    // wall-bounce backoff
export const CONVEYOR_SPEED_TILES = 4.0;      // horizontal push while standing on a conveyor
export const TURRET_TRACK_SPEED = 3.0;        // rad/sec — how fast the turret barrel rotates toward the player

// ----- Timing (seconds) -----

export const PAUSE_TIME_SEC = 0.1;            // brief delay at apex / after rebound
// How long the death animation plays before the player respawns at spawn.
// Long enough for the body to clearly fall off-screen + spin a few times.
export const DEATH_PAUSE_SEC = 1.2;
// After a portal teleports the player, BOTH portals in the pair disable
// for this many seconds — prevents the player materializing inside the
// partner from immediately ping-ponging back. 0.3s is enough for any
// reasonable forward velocity to clear the partner's overlap area.
export const PORTAL_COOLDOWN_SEC = 0.3;
// Fade-to-black duration for cross-page teleport / exit transitions.
// One leg (fade-out OR fade-in); the full transition is 2 × this.
export const FADE_DURATION_MS = 200;

// ----- Death animation -----

// Initial upward "pop" height (in tiles) when the player dies. Computed
// into a velocity via sqrt(2 * gravity * height), same formula as a jump.
export const DEATH_POP_TILES = 2.0;
// Visual rotation rate while dying, in radians/sec. ~6 rad/s ≈ one full
// rotation per second.
export const DEATH_SPIN_RAD_PER_SEC = 6.0;

// ----- Visuals -----

export const COLOR_PLAYER = 0x4ca6ff;         // sky blue (matches Godot COLOR_PLAYER)
export const COLOR_WALL = 0x73757f;           // gray (matches Godot COLOR_WALL)
export const COLOR_SPIKE = 0xd84040;          // red (matches Godot COLOR_SPIKE)
export const COLOR_SPIKE_PLATE = 0x73757f;    // matches wall — the spike's mounting backplate IS a wall
export const COLOR_COIN = 0xffd933;           // bright yellow (matches Godot COLOR_COIN)
export const COLOR_GLASS = 0x8cd9ff;          // light cyan (matches Godot COLOR_GLASS)
export const COLOR_CONVEYOR = 0x666c8c;       // muted blue-gray (matches Godot COLOR_CONVEYOR)
export const COLOR_CANNON = 0x4d4d52;         // dark gray (matches Godot COLOR_CANNON)
export const COLOR_CANNON_BARREL = 0x8c8c99;  // lighter gray (matches Godot COLOR_CANNON_BARREL)
export const COLOR_TURRET_HUB = 0xd9d933;     // bright yellow — marks the rotation pivot for turrets
export const COLOR_BULLET = 0xf27240;         // orange-red (matches Godot bullet color)
export const COLOR_GEAR = 0x999999;           // medium gray (the disc)
export const COLOR_GEAR_SPOKE = 0x333333;     // dark gray (the rotating spokes)
export const COLOR_GEAR_HUB = 0xff9933;       // bright orange (the center hub — makes spin readable)
export const COLOR_TELEPORT = 0xf28c33;       // orange (matches Godot COLOR_TELEPORT) — cross-page teleporter
export const COLOR_EXIT = 0x66d973;           // green (matches Godot COLOR_EXIT) — level goal

// Laser cannon — base + barrel reuse the cannon palette so the family
// is recognizable; the hub + beam are bright red so danger reads at
// a glance and the beam is visible against any tile color.
export const COLOR_LASER_CANNON = 0x4d4d52;
export const COLOR_LASER_CANNON_BARREL = 0x8c8c99;
export const COLOR_LASER_HUB = 0xff3333;
export const COLOR_LASER_BEAM = 0xff3333;
// Rotation speed for cw / ccw modes. π/4 rad/s = 45°/s = one full
// rotation in 8 seconds. Slow enough that players can plan around it.
export const LASER_ROTATION_SPEED = Math.PI / 4;
// Beam thickness in tile units. 0.2 ≈ 9.6 px at TILE_SIZE 48 — thin
// enough to look like a beam, thick enough that the player AABB
// (one tile) reliably overlaps it without sub-pixel near-misses.
export const LASER_BEAM_THICKNESS_TILES = 0.2;

// Six maximally-distinct key colors (mirrors Godot KEY_COLORS). Each
// index pairs a "light" variant for the bright key pickup with a "dark"
// variant for the matching key-wall (so they read as related but
// distinguishable). Dark = 70% of light per channel — same lerp Godot
// uses via Color.darkened(0.3).
export const KEY_COLORS_LIGHT: readonly number[] = [
  0xf24c4c,  // 0 red
  0xf29933,  // 1 orange
  0xf2e633,  // 2 yellow
  0x4cd959,  // 3 green
  0x33bff2,  // 4 cyan
  0xb366f2,  // 5 purple
];
export const KEY_COLORS_DARK: readonly number[] = KEY_COLORS_LIGHT.map((c) => {
  const r = Math.floor(((c >> 16) & 0xff) * 0.7);
  const g = Math.floor(((c >> 8) & 0xff) * 0.7);
  const b = Math.floor((c & 0xff) * 0.7);
  return (r << 16) | (g << 8) | b;
});
export const COLOR_BACKGROUND = '#22252c';    // page background
export const COLOR_GRID = 0x2a2f36;           // subtle grid behind everything
