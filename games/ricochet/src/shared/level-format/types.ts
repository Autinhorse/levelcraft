// Level JSON schema. Matches the format the (frozen) Godot editor writes,
// so godot/levels/*.json round-trips through this loader unchanged.
//
// All element-type arrays are optional so the loader stays forward-compat
// with future schema additions and backward-compat with sparse pages
// (Godot writes empty arrays for unused element types; this format
// tolerates both omission and []).

export interface LevelData {
  id: string;
  name: string;
  exit: ExitPoint;
  pages: PageData[];
}

export interface ExitPoint {
  page: number;
  x: number;
  y: number;
}

export interface PageData {
  /** Row-major character grid. 'W' = wall, '.' = empty, 'C' = coin.
   *  All rows must be the same length. */
  tiles: string[];
  spawn: Cell;
  // Optional element arrays — populated incrementally as Phaser ports
  // each element type. Loader leaves unknown / unused arrays alone.
  teleports?: Teleport[];
  spikes?: Spike[];
  glass_walls?: GlassWall[];
  cannons?: Cannon[];
  conveyors?: Conveyor[];
  spike_blocks?: SpikeBlock[];
  keys?: Key[];
  key_walls?: KeyWall[];
  gears?: Gear[];
  portals?: Portal[];
  turrets?: Turret[];
  laser_cannons?: LaserCannon[];
  text_labels?: TextLabel[];
}

export interface Cell {
  x: number;
  y: number;
}

export type CardinalDir = 'up' | 'down' | 'left' | 'right';
export type ConveyorDir = 'cw' | 'ccw';

export interface Teleport extends Cell {
  target_page: number;
}

export interface Spike extends Cell {
  dir: CardinalDir;
  /** Optional extension cycle: extended (lethal) for `duration`,
   *  retracted (passable) for `downtime`. Both default to 0; a duration
   *  of 0 means "always extended" (legacy + the placement default). */
  duration?: number;
  downtime?: number;
}

export interface GlassWall extends Cell {
  delay: number;
}

export interface Cannon extends Cell {
  dir: CardinalDir;
  period: number;
  bullet_speed: number;
}

export interface Conveyor extends Cell {
  dir: ConveyorDir;
}

// SpikeBlock optionally carries the same extension cycle as Spike —
// duration of 0 means "always extended" (legacy + placement default).
export interface SpikeBlock extends Cell {
  duration?: number;
  downtime?: number;
}

export interface Key extends Cell {
  color: number;
}

export interface KeyWall extends Cell {
  color: number;
}

export interface Gear extends Cell {
  /** Diameter in tiles. The gear is anchored at its center cell. */
  size: number;
  /** Movement speed along the path in tiles/sec. */
  speed: number;
  /** Visual rotation rate in radians/sec. */
  spin: number;
  waypoints: Cell[];
  closed: boolean;
}

export interface Portal {
  color: number;
  /** Either one (orphan, non-functional) or two (paired) cells. */
  points: Cell[];
}

export interface Turret extends Cell {
  period: number;
  bullet_speed: number;
}

export type LaserRotateMode = 'none' | 'cw' | 'ccw';

export interface LaserCannon extends Cell {
  /** Initial beam direction (also the only direction in 'none' rotate mode). */
  dir: CardinalDir;
  /** 'none' = static; 'cw' / 'ccw' = continuous rotation at LASER_ROTATION_SPEED. */
  rotate: LaserRotateMode;
  /** Beam-on duration in seconds. 0 = continuous fire (no off phase). */
  duration: number;
  /** Beam-off duration in seconds. Ignored when duration === 0. */
  downtime: number;
}

// Decorative multi-cell text overlay. (x, y) is the top-left cell;
// width / height are in cells. Purely visual at runtime — no body, no
// hazard, no interaction. Used for level-author-provided hints, signs,
// and similar in-world text.
export interface TextLabel extends Cell {
  width: number;
  height: number;
  text: string;
  /** Font size in pixels. Optional for backward compat — missing
   *  defaults to 16 in both editor and runtime renderers. */
  font_size?: number;
}
