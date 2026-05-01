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

// ----- Timing (seconds) -----

export const PAUSE_TIME_SEC = 0.1;            // brief delay at apex / after rebound

// ----- Visuals -----

export const COLOR_PLAYER = 0x4ca6ff;         // sky blue (matches Godot COLOR_PLAYER)
export const COLOR_WALL = 0x73757f;           // gray (matches Godot COLOR_WALL)
export const COLOR_BACKGROUND = '#22252c';    // page background
export const COLOR_GRID = 0x2a2f36;           // subtle grid behind everything
