import Phaser from 'phaser';

import { GRAVITY_TILES, TILE_SIZE } from './game/config/feel';
import { PlayScene } from './game/scenes/PlayScene';

// Mirrors the Godot project's design size so Phase-2 ports can copy
// pixel-coordinate constants over without rescaling math.
const GAME_WIDTH = 1600;
const GAME_HEIGHT = 960;

const config: Phaser.Types.Core.GameConfig = {
  type: Phaser.WEBGL,
  width: GAME_WIDTH,
  height: GAME_HEIGHT,
  parent: 'game',
  backgroundColor: '#22252c',
  scale: {
    mode: Phaser.Scale.FIT,
    autoCenter: Phaser.Scale.CENTER_BOTH,
    // Belt-and-suspenders for the FIT mode: don't let Phaser resize the
    // #game parent to match canvas dimensions, since #game already has
    // explicit 100vw/100vh in index.html and we want that to be authoritative.
    expandParent: false,
  },
  physics: {
    default: 'arcade',
    arcade: {
      // World gravity is the player's gravity. The Player class toggles
      // body.allowGravity per state so flying / paused / rebound states
      // stay flat while falling / jumping / idle states are gravity-driven.
      gravity: { x: 0, y: GRAVITY_TILES * TILE_SIZE },
      debug: false,
    },
  },
  scene: [PlayScene],
};

new Phaser.Game(config);
