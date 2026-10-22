// Hand-drawn ink for the page, drawn at runtime with Rough.js so every stroke wobbles a little
// differently, like a page from a sketchbook. Nothing here is required to read the page: until a
// drawing exists, CSS shows a plain outline instead.
import rough from 'roughjs';

type Rough = ReturnType<typeof rough.svg>;

export const randomSeed = (): number => Math.floor(Math.random() * 2 ** 31);
const reduceMotion = (): boolean => window.matchMedia('(prefers-reduced-motion: reduce)').matches;

function ink(svg: SVGSVGElement): Rough {
  svg.replaceChildren();
  return rough.svg(svg);
}

const stroke = (seed: number, width = 1.6) => ({
  seed,
  stroke: 'currentColor',
  strokeWidth: width,
  roughness: 1.15,
  bowing: 0.9,
});

/** A box outline. `double` adds a second inset line, like the RPG dialogue frames. */
export function drawBox(svg: SVGSVGElement, w: number, h: number, seed = randomSeed(), double = false): void {
  const rc = ink(svg);
  svg.setAttribute('viewBox', `0 0 ${w} ${h}`);
  svg.appendChild(rc.rectangle(2, 2, w - 4, h - 4, stroke(seed)));
  if (double && w > 24 && h > 24) {
    svg.appendChild(rc.rectangle(7, 7, w - 14, h - 14, { ...stroke(seed + 1, 1), roughness: 0.9 }));
  }
}

/** Two loose horizontal strokes. */
export function drawRule(svg: SVGSVGElement, w: number, seed = randomSeed()): void {
  const rc = ink(svg);
  svg.setAttribute('viewBox', `0 0 ${w} 12`);
  svg.appendChild(rc.line(1, 3, w - 1, 3, stroke(seed, 1.5)));
  svg.appendChild(rc.line(1, 9, w - 1, 9, stroke(seed + 7, 1.2)));
}

/** The red 共鳴 seal frame, hatched like a half-inked stamp. */
export function drawSeal(svg: SVGSVGElement, color: string, seed = randomSeed()): void {
  const rc = ink(svg);
  svg.setAttribute('viewBox', '0 0 100 100');
  svg.appendChild(
    rc.rectangle(8, 8, 84, 84, {
      seed,
      roughness: 2.3,
      bowing: 1.6,
      stroke: color,
      strokeWidth: 2.6,
      fill: color,
      fillStyle: 'hachure',
      hachureAngle: 52,
      hachureGap: 9,
      fillWeight: 0.65,
    }),
  );
}

// A pointing hand drawn for Kyōmei, in a 32×32 box: cuff, palm, three curled fingers, index
// finger pointing right and a thumb resting on top.
const HAND = [
  'M7.5 12 Q7.5 10.5 9.5 10.5 L12.4 10.5 Q13.1 7.2 15.6 7.6 Q17.3 8 16.7 10.5 L28.6 10.5',
  'Q31 10.5 31 13 Q31 15.5 28.6 15.5 L19.4 15.5 Q21.4 15.8 21.4 17.8 Q21.4 19.6 19.4 19.6',
  'Q21.3 19.9 21.3 21.7 Q21.3 23.4 19.2 23.4 Q20.7 23.8 20.3 25 Q19.9 26.2 18.2 26.2',
  'L9.5 26.2 Q7.5 26.2 7.5 24.2 Z',
].join(' ');

export function drawHand(svg: SVGSVGElement, seed = randomSeed()): void {
  const rc = ink(svg);
  svg.setAttribute('viewBox', '0 0 32 32');
  const s = { seed, roughness: 0.6, bowing: 0.4, stroke: 'currentColor', strokeWidth: 1.5, disableMultiStroke: true };
  const palm = rc.path(HAND, { ...s, fill: 'var(--bg)', fillStyle: 'solid' });
  svg.appendChild(palm);
  svg.appendChild(rc.rectangle(2.5, 11.2, 5, 14.4, s)); // cuff
}

/** Concentric resonance rings; each <g> gets class "ring" so CSS can make them breathe. */
export function drawRings(svg: SVGSVGElement, cx: number, cy: number, radii: number[], seed = randomSeed()): void {
  radii.forEach((r, i) => {
    const rc = rough.svg(svg);
    const g = rc.circle(cx, cy, r * 2, { ...stroke(seed + i * 13, i === 0 ? 2 : 1.4), roughness: 1.4 });
    g.classList.add('ring');
    svg.appendChild(g);
  });
}

/** A smooth, wobbly curve through points (used for the EQ sketch). */
export function drawCurve(svg: SVGSVGElement, points: [number, number][], seed = randomSeed()): void {
  const rc = rough.svg(svg);
  svg.appendChild(rc.curve(points, { ...stroke(seed, 2.2), roughness: 0.9 }));
}

// ── Auto-wiring ──────────────────────────────────────────────────────────────

function sketchLayer(el: HTMLElement): SVGSVGElement {
  let svg = el.querySelector<SVGSVGElement>(':scope > .sketch-ink');
  if (!svg) {
    svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.classList.add('sketch-ink');
    svg.setAttribute('aria-hidden', 'true');
    svg.setAttribute('preserveAspectRatio', 'none');
    el.prepend(svg);
  }
  return svg;
}

function render(el: HTMLElement, seed: number): void {
  const { width, height } = el.getBoundingClientRect();
  if (width < 4 || height < 4) return;
  const svg = sketchLayer(el);
  if (el.dataset.sketch === 'rule') drawRule(svg, width, seed);
  else drawBox(svg, width, height, seed, el.dataset.sketch === 'double');
  el.dataset.drawn = '';
}

/** Draws every [data-sketch] element, redraws on resize, and re-rolls the ink on hover. */
export function sketchAll(root: ParentNode = document): void {
  const elements = Array.from(root.querySelectorAll<HTMLElement>('[data-sketch]'));
  const seeds = new WeakMap<HTMLElement, number>();
  const observer = new ResizeObserver((entries) => {
    for (const entry of entries) {
      const el = entry.target as HTMLElement;
      render(el, seeds.get(el) ?? randomSeed());
    }
  });
  for (const el of elements) {
    seeds.set(el, randomSeed());
    observer.observe(el);
    if (el.dataset.reroll !== 'off') {
      let last = 0;
      el.addEventListener('pointerenter', () => {
        if (reduceMotion()) return;
        const now = performance.now();
        if (now - last < 160) return;
        last = now;
        const seed = randomSeed();
        seeds.set(el, seed);
        render(el, seed);
      });
    }
  }
}
