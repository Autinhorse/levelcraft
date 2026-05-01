import Phaser from 'phaser';

import { BootScene } from './game/scenes/BootScene';

// Mirrors the Godot project's design size so Phase-2 ports can copy
// pixel-coordinate constants over without rescaling math.
const GAME_WIDTH = 1600;
const GAME_HEIGHT = 960;

const config: Phaser.Types.Core.GameConfig = {
  type: Phaser.WEBGL,
  width: GAME_WIDTH,
  height: GAME_HEIGHT,
  parent: 'game',
  backgroundColor: '#1a1d22',
  scale: {
    mode: Phaser.Scale.FIT,
    autoCenter: Phaser.Scale.CENTER_BOTH,
  },
  scene: [BootScene],
};

new Phaser.Game(config);
