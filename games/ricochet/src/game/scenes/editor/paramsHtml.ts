import { KEY_COLORS_LIGHT } from '../../config/feel';
import type {
  CardinalDir,
  ConveyorDir,
  LaserRotateMode,
} from '../../../shared/level-format/types';
import type { SelectedElement } from './types';

// All HTML builders for the editor's right-side params panel. Pure
// functions of their inputs — every state needed (current values,
// page count, gear-edit flag) is passed explicitly. EditScene
// composes them and writes the resulting string into the panel's
// innerHTML.
//
// The dataset attribute namespaces are split so the click router can
// route by attribute prefix:
//   data-param-*  →  tool-sticky params (next placement uses these)
//   data-elem-*   →  per-instance edits to the selected element
//
// `adjustElementProp` (mutation half of per-instance numeric edits)
// stays in EditScene — the HTML side here only emits the buttons.

// ---- Per-instance params (data-elem-*) ----

export function elemHeader(name: string): string {
  return `<div class="palette-section-label">${name.toUpperCase()}</div>`;
}

export function elemDirHtml(current: CardinalDir): string {
  const labels: Record<CardinalDir, string> = { up: '↑', down: '↓', left: '←', right: '→' };
  const buttons = (['up', 'down', 'left', 'right'] as CardinalDir[])
    .map((d) => {
      const sel = d === current ? ' selected' : '';
      return `<button data-elem-dir="${d}" class="palette-btn${sel}">${labels[d]}</button>`;
    })
    .join('');
  return `
    <div class="palette-section-label">DIRECTION</div>
    <div class="palette-grid-2">${buttons}</div>
  `;
}

export function elemConveyorDirHtml(current: ConveyorDir): string {
  const labels: Record<ConveyorDir, string> = { cw: 'CW →', ccw: 'CCW ←' };
  const buttons = (['cw', 'ccw'] as ConveyorDir[])
    .map((d) => {
      const sel = d === current ? ' selected' : '';
      return `<button data-elem-conveyor-dir="${d}" class="palette-btn${sel}">${labels[d]}</button>`;
    })
    .join('');
  return `
    <div class="palette-section-label">DIRECTION</div>
    <div class="palette-grid-2">${buttons}</div>
  `;
}

export function elemColorHtml(current: number): string {
  const buttons = KEY_COLORS_LIGHT.map((color, i) => {
    const hex = '#' + color.toString(16).padStart(6, '0');
    const sel = i === current ? ' selected' : '';
    return `<button data-elem-color="${i}" class="palette-btn palette-color${sel}" style="background:${hex}"></button>`;
  }).join('');
  return `
    <div class="palette-section-label">COLOR</div>
    <div class="palette-color-row">${buttons}</div>
  `;
}

export function elemLaserRotateHtml(current: LaserRotateMode): string {
  const labels: Record<LaserRotateMode, string> = { none: 'None', cw: 'CW', ccw: 'CCW' };
  const buttons = (['none', 'cw', 'ccw'] as LaserRotateMode[])
    .map((m) => {
      const sel = m === current ? ' selected' : '';
      return `<button data-elem-laser-rotate="${m}" class="palette-btn${sel}">${labels[m]}</button>`;
    })
    .join('');
  return `
    <div class="palette-section-label">ROTATE</div>
    <div class="palette-grid-2">${buttons}</div>
  `;
}

export function elemStepperHtml(
  label: string,
  valueText: string,
  propName: string,
): string {
  return `
    <div class="palette-section-label">${label.toUpperCase()}</div>
    <div class="palette-stepper">
      <button data-elem-prop="${propName}" data-elem-step="-1" class="palette-btn palette-stepper-btn">−</button>
      <span class="palette-stepper-value">${valueText}</span>
      <button data-elem-prop="${propName}" data-elem-step="1" class="palette-btn palette-stepper-btn">+</button>
    </div>
  `;
}

// Per-instance params dispatch — picks the right block per element
// `kind`. `pageCount` and `isEditingGearPath` come from the caller's
// scene state since they're context-dependent. The gear case embeds
// the "EDIT GEAR PATH" hint + Done button only when this gear is the
// current path-edit target.
export function elementParamHtml(
  sel: SelectedElement,
  ctx: { pageCount: number; isEditingGearPath: boolean },
): string {
  switch (sel.kind) {
    case 'glass_wall':
      return elemHeader('Glass Wall')
        + elemStepperHtml('Delay', sel.ref.delay.toFixed(1) + ' s', 'delay');
    case 'spike_block': {
      const dur = sel.ref.duration ?? 0;
      const down = sel.ref.downtime ?? 3.0;
      const durLabel = dur === 0 ? 'always extended' : `${dur.toFixed(1)} s`;
      return elemHeader('Spike Block')
        + elemStepperHtml('Extend', durLabel, 'duration')
        + elemStepperHtml('Retract', `${down.toFixed(1)} s`, 'downtime');
    }
    case 'spike': {
      const dur = sel.ref.duration ?? 0;
      const down = sel.ref.downtime ?? 3.0;
      const durLabel = dur === 0 ? 'always extended' : `${dur.toFixed(1)} s`;
      return elemHeader('Spike')
        + elemDirHtml(sel.ref.dir)
        + elemStepperHtml('Extend', durLabel, 'duration')
        + elemStepperHtml('Retract', `${down.toFixed(1)} s`, 'downtime');
    }
    case 'conveyor':
      return elemHeader('Conveyor')
        + elemConveyorDirHtml(sel.ref.dir);
    case 'cannon':
      return elemHeader('Cannon')
        + elemDirHtml(sel.ref.dir)
        + elemStepperHtml('Period', sel.ref.period.toFixed(1) + ' s', 'period')
        + elemStepperHtml('Bullet speed', sel.ref.bullet_speed.toFixed(1) + ' t/s', 'bullet_speed');
    case 'turret':
      return elemHeader('Turret')
        + elemStepperHtml('Period', sel.ref.period.toFixed(1) + ' s', 'period')
        + elemStepperHtml('Bullet speed', sel.ref.bullet_speed.toFixed(1) + ' t/s', 'bullet_speed');
    case 'gear': {
      const closedLabel = sel.ref.closed ? 'Closed loop' : 'Open path';
      const pathBlock = ctx.isEditingGearPath
        ? `<div class="palette-section-label">EDIT GEAR PATH</div>
           <div class="palette-hint">
             Click empty cells to add waypoints.<br>
             Click another gear to switch edit target.<br>
             Click this gear's center to close the loop.
           </div>
           <button data-action="gear-finish-open" class="palette-btn palette-btn-full">Done (open)</button>`
        : '';
      return elemHeader('Gear')
        + elemStepperHtml('Size', `${sel.ref.size} t`, 'size')
        + elemStepperHtml('Speed', sel.ref.speed.toFixed(1) + ' t/s', 'speed')
        + elemStepperHtml('Spin', sel.ref.spin.toFixed(1) + ' r/s', 'spin')
        + `<button data-elem-toggle="closed" class="palette-btn palette-btn-full">${closedLabel}</button>`
        + pathBlock;
    }
    case 'key':
      return elemHeader('Key')
        + elemColorHtml(sel.ref.color);
    case 'key_wall':
      return elemHeader('Key Wall')
        + elemColorHtml(sel.ref.color);
    case 'teleport': {
      const max = ctx.pageCount - 1;
      const v = Math.max(0, Math.min(sel.ref.target_page, max));
      return elemHeader('Teleport')
        + elemStepperHtml('Target page', `${v + 1} / ${max + 1}`, 'target_page');
    }
    case 'laser_cannon': {
      const lc = sel.ref;
      const durLabel = lc.duration === 0 ? 'continuous' : `${lc.duration.toFixed(1)} s`;
      return elemHeader('Laser Cannon')
        + elemDirHtml(lc.dir)
        + elemLaserRotateHtml(lc.rotate)
        + elemStepperHtml('Duration', durLabel, 'duration')
        + elemStepperHtml('Downtime', lc.downtime.toFixed(1) + ' s', 'downtime');
    }
    case 'text_label': {
      // The textarea uses an `input` event listener on the palette
      // (event-delegated) rather than re-rendering on each keystroke,
      // so typing here doesn't blow away its own focus / selection.
      // Width / height steppers DO re-render the panel — clicking
      // them implies the user is done typing for the moment, which
      // matches the loss of focus the re-render incurs.
      const ref = sel.ref;
      // Escape HTML special chars in textarea body (preserves
      // newlines naturally — the textarea handles \n).
      const safeText = ref.text
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
      return elemHeader('Text')
        + elemStepperHtml('Width', `${ref.width} cells`, 'width')
        + elemStepperHtml('Height', `${ref.height} cells`, 'height')
        + elemStepperHtml('Font size', `${ref.font_size ?? 16} px`, 'font_size')
        + `<div class="palette-section-label">CONTENT</div>
           <textarea data-elem-text-input class="palette-textarea" rows="5">${safeText}</textarea>`;
    }
  }
}

// ---- Tool-sticky params (data-param-*) ----

export function dirParamHtml(current: string, dirs: string[]): string {
  const labels: Record<string, string> = {
    up: '↑', down: '↓', left: '←', right: '→',
    cw: 'CW →', ccw: 'CCW ←',
  };
  const buttons = dirs
    .map((d) => {
      const sel = d === current ? ' selected' : '';
      return `<button data-param-dir="${d}" class="palette-btn${sel}">${labels[d]}</button>`;
    })
    .join('');
  return `
    <div class="palette-section-label">DIRECTION</div>
    <div class="palette-grid-2">${buttons}</div>
  `;
}

export function colorParamHtml(current: number): string {
  const buttons = KEY_COLORS_LIGHT.map((color, i) => {
    const hex = '#' + color.toString(16).padStart(6, '0');
    const sel = i === current ? ' selected' : '';
    return `<button data-param-color="${i}" class="palette-btn palette-color${sel}" style="background:${hex}"></button>`;
  }).join('');
  return `
    <div class="palette-section-label">COLOR</div>
    <div class="palette-color-row">${buttons}</div>
  `;
}

// Stepper for teleport's target_page. `pageCount` from caller's
// `level.pages.length`.
export function teleportParamHtml(currentTarget: number, pageCount: number): string {
  const max = pageCount - 1;
  const value = Math.max(0, Math.min(currentTarget, max));
  return `
    <div class="palette-section-label">TARGET PAGE</div>
    <div class="palette-stepper">
      <button data-param-step="-1" class="palette-btn palette-stepper-btn">−</button>
      <span class="palette-stepper-value">${value + 1} / ${max + 1}</span>
      <button data-param-step="1" class="palette-btn palette-stepper-btn">+</button>
    </div>
  `;
}

export function laserCannonParamHtml(p: {
  dir: CardinalDir;
  rotate: LaserRotateMode;
  duration: number;
  downtime: number;
}): string {
  const dirLabels: Record<CardinalDir, string> = {
    up: '↑', down: '↓', left: '←', right: '→',
  };
  const dirButtons = (['up', 'down', 'left', 'right'] as CardinalDir[])
    .map((d) => {
      const sel = d === p.dir ? ' selected' : '';
      return `<button data-param-laser-dir="${d}" class="palette-btn${sel}">${dirLabels[d]}</button>`;
    })
    .join('');
  const rotLabels: Record<LaserRotateMode, string> = {
    none: 'None', cw: 'CW', ccw: 'CCW',
  };
  const rotButtons = (['none', 'cw', 'ccw'] as LaserRotateMode[])
    .map((m) => {
      const sel = m === p.rotate ? ' selected' : '';
      return `<button data-param-laser-rotate="${m}" class="palette-btn${sel}">${rotLabels[m]}</button>`;
    })
    .join('');
  const durLabel = p.duration === 0 ? 'continuous' : `${p.duration.toFixed(1)} s`;
  const downLabel = `${p.downtime.toFixed(1)} s`;
  return `
    <div class="palette-section-label">DIRECTION</div>
    <div class="palette-grid-2">${dirButtons}</div>
    <div class="palette-section-label">ROTATE</div>
    <div class="palette-grid-2">${rotButtons}</div>
    <div class="palette-section-label">DURATION</div>
    <div class="palette-stepper">
      <button data-param-laser-dur="-1" class="palette-btn palette-stepper-btn">−</button>
      <span class="palette-stepper-value">${durLabel}</span>
      <button data-param-laser-dur="1" class="palette-btn palette-stepper-btn">+</button>
    </div>
    <div class="palette-section-label">DOWNTIME</div>
    <div class="palette-stepper">
      <button data-param-laser-down="-1" class="palette-btn palette-stepper-btn">−</button>
      <span class="palette-stepper-value">${downLabel}</span>
      <button data-param-laser-down="1" class="palette-btn palette-stepper-btn">+</button>
    </div>
  `;
}

export function textToolParamHtml(p: { width: number; height: number }): string {
  return `
    <div class="palette-section-label">WIDTH</div>
    <div class="palette-stepper">
      <button data-param-text-w="-1" class="palette-btn palette-stepper-btn">−</button>
      <span class="palette-stepper-value">${p.width} cells</span>
      <button data-param-text-w="1" class="palette-btn palette-stepper-btn">+</button>
    </div>
    <div class="palette-section-label">HEIGHT</div>
    <div class="palette-stepper">
      <button data-param-text-h="-1" class="palette-btn palette-stepper-btn">−</button>
      <span class="palette-stepper-value">${p.height} cells</span>
      <button data-param-text-h="1" class="palette-btn palette-stepper-btn">+</button>
    </div>
    <div class="palette-hint">
      Place a label, then switch to <b>Select / Move</b> and click it
      to edit its text content.
    </div>
  `;
}
