// Title-screen behaviour: typewriter text, RPG menus with a pointing hand, the seal, the
// WHITE SPACE theme and opt-in sound. Everything degrades to plain HTML without it.
import { drawHand, drawSeal } from './sketch';

const $$ = <T extends Element>(sel: string, root: ParentNode = document) => Array.from(root.querySelectorAll<T>(sel));
const reduceMotion = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;

const store = {
  get(key: string): string | null {
    try { return localStorage.getItem(key); } catch { return null; }
  },
  set(key: string, value: string) {
    try { localStorage.setItem(key, value); } catch { /* private mode: just not remembered */ }
  },
};

// ── Typewriter ──────────────────────────────────────────────────────────────
// A hidden spacer keeps the layout; a clipped copy widens in steps (see .type in global.css).
export function typewrite(el: HTMLElement, text: string, secondsPerChar = 0.045): void {
  if (reduceMotion() || !text) {
    el.textContent = text;
    return;
  }
  const spacer = document.createElement('span');
  spacer.className = 'type-spacer';
  spacer.setAttribute('aria-hidden', 'true');
  spacer.textContent = text;
  const live = document.createElement('span');
  live.className = 'type-text';
  live.textContent = text;
  el.style.setProperty('--chars', String(text.length));
  el.style.setProperty('--type-duration', `${Math.max(0.3, text.length * secondsPerChar).toFixed(2)}s`);
  el.replaceChildren(spacer, live);
}

/**
 * Multi-line dialogue typing. Screen readers get the whole sentence at once from a visually
 * hidden copy; the visible copy is typed out and is hidden from assistive technology.
 */
let typingTimer: number | undefined;
export function typeLines(el: HTMLElement, text: string, msPerChar = 16): void {
  window.clearInterval(typingTimer);
  const full = document.createElement('span');
  full.className = 'sr-only';
  full.textContent = text;
  const shown = document.createElement('span');
  shown.setAttribute('aria-hidden', 'true');
  el.replaceChildren(full, shown);
  if (reduceMotion()) {
    shown.textContent = text;
    return;
  }
  let i = 0;
  typingTimer = window.setInterval(() => {
    i = Math.min(text.length, i + 2);
    shown.textContent = text.slice(0, i);
    if (i >= text.length) window.clearInterval(typingTimer);
  }, msPerChar * 2);
}

// ── Sound (off by default; synthesized, no audio files) ─────────────────────
let audio: AudioContext | null = null;
let sfxOn = store.get('kyomei-sfx') === '1';

export function blip(freq = 880, length = 0.06): void {
  if (!sfxOn) return;
  try {
    audio ??= new AudioContext();
    if (audio.state === 'suspended') void audio.resume();
    const t = audio.currentTime;
    const osc = audio.createOscillator();
    const gain = audio.createGain();
    osc.type = 'triangle';
    osc.frequency.setValueAtTime(freq, t);
    osc.frequency.exponentialRampToValueAtTime(freq * 1.5, t + length); // a small rising "ring"
    gain.gain.setValueAtTime(0.0001, t);
    gain.gain.exponentialRampToValueAtTime(0.05, t + 0.008);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + length);
    osc.connect(gain).connect(audio.destination);
    osc.start(t);
    osc.stop(t + length + 0.02);
  } catch {
    /* no audio device */
  }
}

// ── Menus ───────────────────────────────────────────────────────────────────
function menus(): void {
  for (const menu of $$<HTMLElement>('[data-menu]')) {
    const hand = menu.querySelector<SVGSVGElement>('[data-hand]');
    const items = $$<HTMLElement>('[data-menu-item]', menu);
    if (!hand || items.length === 0) continue;
    drawHand(hand);

    const point = (item: HTMLElement) => {
      const box = item.getBoundingClientRect();
      const host = menu.getBoundingClientRect();
      const size = hand.getBoundingClientRect().height || 32;
      menu.style.setProperty('--hand-y', `${Math.round(box.top - host.top + box.height / 2 - size / 2)}px`);
      menu.style.setProperty('--hand-x', `${Math.round(box.left - host.left - size - 6)}px`);
      menu.classList.add('is-active');
    };

    items.forEach((item, index) => {
      item.addEventListener('pointerenter', () => { point(item); blip(880); });
      item.addEventListener('focus', () => point(item));
      item.addEventListener('click', () => point(item));
      item.addEventListener('keydown', (e) => {
        const next = e.key === 'ArrowDown' ? index + 1 : e.key === 'ArrowUp' ? index - 1 : null;
        if (next === null) return;
        e.preventDefault();
        const target = items[(next + items.length) % items.length];
        target.focus();
        if (target.getAttribute('role') === 'tab') target.click();
      });
    });
    menu.addEventListener('pointerleave', () => {
      const selected = items.find((i) => i.getAttribute('aria-selected') === 'true');
      if (selected) point(selected);
      else menu.classList.remove('is-active');
    });
    const selected = items.find((i) => i.getAttribute('aria-selected') === 'true');
    if (selected) requestAnimationFrame(() => point(selected));
    window.addEventListener('resize', () => {
      const current = items.find((i) => i.getAttribute('aria-selected') === 'true');
      if (current) point(current);
    });
  }
}

// ── Showcase tabs ───────────────────────────────────────────────────────────
function tabs(): void {
  const list = document.querySelector<HTMLElement>('[data-tablist]');
  const caption = document.querySelector<HTMLElement>('[data-caption-target]');
  if (!list) return;
  const tabsEls = $$<HTMLButtonElement>('[role="tab"]', list);
  for (const tab of tabsEls) {
    tab.addEventListener('click', () => {
      for (const other of tabsEls) {
        const on = other === tab;
        other.setAttribute('aria-selected', String(on));
        other.tabIndex = on ? 0 : -1;
        const panel = document.getElementById(other.getAttribute('aria-controls') ?? '');
        if (panel) panel.hidden = !on;
      }
      if (caption) typeLines(caption, tab.dataset.caption ?? '');
      blip(660, 0.08);
    });
  }
}

// ── Mobile menu ─────────────────────────────────────────────────────────────
function mobileMenu(): void {
  const button = document.querySelector<HTMLButtonElement>('[data-mobile-menu-button]');
  const panel = document.querySelector<HTMLElement>('[data-mobile-menu]');
  if (!button || !panel) return;
  const set = (open: boolean) => {
    panel.hidden = !open;
    button.setAttribute('aria-expanded', String(open));
    button.textContent = open ? 'Close' : 'Menu';
    if (open) panel.querySelector<HTMLElement>('[data-menu-item]')?.focus();
  };
  button.addEventListener('click', () => set(panel.hidden));
  panel.addEventListener('click', (e) => {
    if ((e.target as HTMLElement).closest('[data-close-menu]')) set(false);
  });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !panel.hidden) { set(false); button.focus(); }
  });
}

// ── The seal ────────────────────────────────────────────────────────────────
function seal(): void {
  const button = document.querySelector<HTMLButtonElement>('[data-stamp]');
  const svg = document.querySelector<SVGSVGElement>('[data-stamp-ink]');
  if (!button || !svg) return;
  const ink = () => drawSeal(svg, getComputedStyle(document.documentElement).getPropertyValue('--ink').trim() || '#c8102e');
  ink();
  button.addEventListener('click', () => { ink(); blip(520, 0.1); });
  if (!reduceMotion()) setInterval(() => { if (!document.hidden) ink(); }, 4500);
}

// ── Options: WHITE SPACE and SFX ────────────────────────────────────────────
function options(): void {
  const space = document.querySelector<HTMLButtonElement>('[data-space-toggle]');
  const sfx = document.querySelector<HTMLButtonElement>('[data-sfx-toggle]');
  const root = document.documentElement;
  if (space) {
    space.setAttribute('aria-checked', String(root.dataset.space === 'white'));
    space.addEventListener('click', () => {
      const white = root.dataset.space !== 'white';
      if (white) root.dataset.space = 'white';
      else delete root.dataset.space;
      store.set('kyomei-space', white ? 'white' : 'black');
      space.setAttribute('aria-checked', String(white));
      blip(white ? 990 : 440);
    });
  }
  if (sfx) {
    sfx.setAttribute('aria-checked', String(sfxOn));
    sfx.addEventListener('click', () => {
      sfxOn = !sfxOn;
      store.set('kyomei-sfx', sfxOn ? '1' : '0');
      sfx.setAttribute('aria-checked', String(sfxOn));
      blip(1200, 0.07);
    });
  }
  for (const el of $$<HTMLElement>('[data-blip]')) el.addEventListener('pointerenter', () => blip(780, 0.04));
}

export function interactions(): void {
  for (const el of $$<HTMLElement>('[data-typewrite]')) typewrite(el, el.dataset.typewrite ?? '');
  menus();
  tabs();
  mobileMenu();
  seal();
  options();
  for (const type of ['pointerdown', 'keydown'] as const) {
    window.addEventListener(type, () => { if (audio?.state === 'suspended') void audio.resume(); }, { passive: true });
  }
}
