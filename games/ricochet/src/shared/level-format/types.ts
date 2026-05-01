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

// SpikeBlock is just a positioned cell; no extra fields today, but kept
// as its own type so future tuning fields can be added without touching
// callers.
export type SpikeBlock = Cell;

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
