import Phaser from 'phaser';

// Phase 1: minimal scene that proves the toolchain. Renders a grid background
// (echoing the Godot editor's grid look) and a centered blue rectangle with a
// "Phaser 4 boot OK" label. Replaced in Phase 2 with the actual game scene.
export class BootScene extends Phaser.Scene {
  constructor() {
    super('BootScene');
  }

  create(): void {
    const { width, height } = this.scale.gameSize;

    // Subtle grid so we can confirm the canvas fills the design size.
    this.drawBackgroundGrid(width, height);

    // Central indicator rectangle.
    this.add.rectangle(width / 2, height / 2 - 40, 240, 120, 0x4a9eff);

    // Status text.
    this.add
      .text(width / 2, height / 2 + 60, 'Phaser 4 boot OK', {
        color: '#cccccc',
        fontSize: '36px',
      })
      .setOrigin(0.5);

    this.add
      .text(width / 2, height / 2 + 110, 'LevelCraft: Ricochet — Phase 1 scaffold', {
        color: '#888888',
        fontSize: '18px',
      })
      .setOrigin(0.5);
  }

  private drawBackgroundGrid(width: number, height: number): void {
    const tile = 48; // matches the Godot game's TILE_SIZE for visual continuity
    const gfx = this.add.graphics();
    gfx.lineStyle(1, 0x2a2f36, 0.6);
    for (let x = 0; x <= width; x += tile) {
      gfx.lineBetween(x, 0, x, height);
    }
    for (let y = 0; y <= height; y += tile) {
      gfx.lineBetween(0, y, width, y);
    }
  }
}
