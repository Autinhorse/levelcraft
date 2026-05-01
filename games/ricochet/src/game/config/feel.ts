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

// ----- Timing (seconds) -----

export const PAUSE_TIME_SEC = 0.1;            // brief delay at apex / after rebound
// How long the death animation plays before the player respawns at spawn.
// Long enough for the body to clearly fall off-screen + spin a few times.
export const DEATH_PAUSE_SEC = 1.2;

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
export const COLOR_BULLET = 0xf27240;         // orange-red (matches Godot bullet color)
export const COLOR_BACKGROUND = '#22252c';    // page background
export const COLOR_GRID = 0x2a2f36;           // subtle grid behind everything
