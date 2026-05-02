import Phaser from 'phaser';

import { COLOR_BACKGROUND } from '../config/feel';

const LEVEL_COUNT = 12;

// Landing screen. Shows a 4×3 grid of "Level 1..12" buttons; clicking
// one starts EditScene with that level's path. Also handles the
// `?level=NN` deep-link by skipping the menu entirely (useful for the
// Play→Edit hand-off in PlayScene's back button, and for bookmarking
// directly to a level during authoring).
export class MenuScene extends Phaser.Scene {
  private overlay: HTMLDivElement | null = null;

  constructor() {
    super('MenuScene');
  }

  create(): void {
    this.cameras.main.setBackgroundColor(COLOR_BACKGROUND);

    // Deep-link via URL (?level=NN). One-shot — if the parameter is
    // present we never show the menu, we just hand off to EditScene.
    const params = new URLSearchParams(window.location.search);
    const levelParam = params.get('level');
    if (levelParam) {
      const padded = String(levelParam).padStart(2, '0');
      this.scene.start('EditScene', { levelPath: `levels/level-${padded}.json` });
      return;
    }

    this.buildOverlay();

    this.events.once(Phaser.Scenes.Events.SHUTDOWN, () => this.destroyOverlay());
    this.events.once(Phaser.Scenes.Events.DESTROY, () => this.destroyOverlay());
  }

  private buildOverlay(): void {
    const overlay = document.createElement('div');
    overlay.className = 'menu-overlay';
    const buttons = Array.from({ length: LEVEL_COUNT }, (_, i) => {
      const n = i + 1;
      const padded = String(n).padStart(2, '0');
      return `<button data-level="${padded}" class="menu-btn">Level ${n}</button>`;
    }).join('');
    overlay.innerHTML = `
      <div class="menu-content">
        <h1 class="menu-title">LevelCraft: Ricochet</h1>
        <p class="menu-subtitle">Select a level to edit</p>
        <div class="menu-grid">${buttons}</div>
      </div>
    `;
    document.body.appendChild(overlay);
    overlay.addEventListener('click', (ev) => this.onOverlayClick(ev));
    this.overlay = overlay;
  }

  private onOverlayClick(ev: MouseEvent): void {
    const target = ev.target as HTMLElement;
    const lvl = target.getAttribute('data-level');
    if (!lvl) return;
    this.scene.start('EditScene', { levelPath: `levels/level-${lvl}.json` });
  }

  private destroyOverlay(): void {
    if (this.overlay) {
      this.overlay.remove();
      this.overlay = null;
    }
  }
}
