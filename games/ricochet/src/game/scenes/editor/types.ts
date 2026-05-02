import type {
  Cannon as CannonData,
  Conveyor as ConveyorData,
  Gear as GearData,
  GlassWall as GlassWallData,
  Key as KeyData,
  KeyWall as KeyWallData,
  LaserCannon as LaserCannonData,
  Spike as SpikeData,
  SpikeBlock as SpikeBlockData,
  Teleport as TeleportData,
  TextLabel as TextLabelData,
  Turret as TurretData,
} from '../../../shared/level-format/types';

// Selection state for the Select tool's per-instance editing. Each
// `ref` is a direct pointer into the level's per-page array, so
// mutating `ref` flows straight back into the saved JSON. The
// discriminated union lets callers narrow on `kind` to access
// type-specific properties (e.g. only spike / cannon / laser_cannon
// carry `dir`).
export type SelectedElement =
  | { kind: 'glass_wall'; ref: GlassWallData }
  | { kind: 'spike_block'; ref: SpikeBlockData }
  | { kind: 'spike'; ref: SpikeData }
  | { kind: 'conveyor'; ref: ConveyorData }
  | { kind: 'cannon'; ref: CannonData }
  | { kind: 'turret'; ref: TurretData }
  | { kind: 'gear'; ref: GearData }
  | { kind: 'key'; ref: KeyData }
  | { kind: 'key_wall'; ref: KeyWallData }
  | { kind: 'teleport'; ref: TeleportData }
  | { kind: 'laser_cannon'; ref: LaserCannonData }
  | { kind: 'text_label'; ref: TextLabelData };
