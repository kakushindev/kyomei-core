// The page's illustrations, re-drawn by hand at runtime. Each [data-art] SVG ships a clean static
// version in the HTML; this replaces it with a wobbling Rough.js drawing and keeps the same shapes.
import rough from 'roughjs';
import { drawCurve, drawRings, randomSeed } from './sketch';

const opts = (seed: number, width = 1.8) => ({ seed, stroke: 'currentColor', strokeWidth: width, roughness: 1.2, bowing: 1 });

function clear(svg: SVGSVGElement) {
  svg.replaceChildren();
  return rough.svg(svg);
}

/** An earbud: rounded head with the speaker grille, and a stem leaning slightly outward. */
function earbud(svg: SVGSVGElement, x: number, y: number, scale: number, seed: number, mirror = false) {
  const rc = rough.svg(svg);
  const k = scale, m = mirror ? -1 : 1;
  svg.appendChild(rc.ellipse(x, y, 44 * k, 38 * k, { ...opts(seed), fill: 'currentColor', fillStyle: 'hachure', hachureGap: 5 * k, fillWeight: 0.5 }));
  svg.appendChild(rc.ellipse(x - 9 * k * m, y - 3 * k, 12 * k, 9 * k, opts(seed + 1, 1.3)));
  const stem: [number, number][] = [
    [x + 4 * k * m, y + 14 * k], [x + 6 * k * m, y + 62 * k], [x + 12 * k * m, y + 68 * k],
    [x + 18 * k * m, y + 62 * k], [x + 18 * k * m, y + 10 * k],
  ];
  svg.appendChild(rc.curve(stem, opts(seed + 2)));
}

function resonance(svg: SVGSVGElement, seed: number) {
  const rc = clear(svg);
  earbud(svg, 62, 120, 0.9, seed, true);
  earbud(svg, 112, 136, 0.9, seed + 5);
  [70, 110, 150].forEach((r, i) => {
    const arc = rc.arc(100, 140, r * 2, r * 2, -0.75, 0.75, false, opts(seed + 10 + i, 2 - i * 0.3));
    arc.classList.add('ring');
    svg.appendChild(arc);
  });
  // A laptop on the right: screen, a tiny 共鳴 seal on it, and the base.
  svg.appendChild(rc.rectangle(282, 82, 136, 92, opts(seed + 20)));
  svg.appendChild(rc.rectangle(292, 92, 116, 72, opts(seed + 21, 1)));
  svg.appendChild(rc.polygon([[262, 186], [438, 186], [424, 204], [276, 204]], opts(seed + 22)));
  svg.appendChild(rc.rectangle(336, 112, 26, 26, {
    seed: seed + 23, stroke: '#c8102e', strokeWidth: 1.6, roughness: 1.6, fill: '#c8102e', fillStyle: 'hachure', hachureGap: 4,
  }));
  svg.classList.add('is-live');
}

function noise(svg: SVGSVGElement, seed: number) {
  clear(svg);
  drawRings(svg, 160, 150, [40, 80, 120], seed);
  earbud(svg, 152, 132, 0.8, seed + 50);
  svg.classList.add('is-live');
}

function meaning(svg: SVGSVGElement, seed: number) {
  clear(svg);
  drawRings(svg, 130, 130, [30, 60, 90], seed);
  drawRings(svg, 230, 130, [30, 60, 90], seed + 100);
  svg.classList.add('is-live');
}

function eq(svg: SVGSVGElement, seed: number) {
  const values = (svg.dataset.values ?? '').split(',').map(Number);
  if (values.length < 2 || values.some(Number.isNaN)) return;
  svg.querySelector('[data-static-curve]')?.remove();
  svg.querySelectorAll('[data-sketched]').forEach((el) => el.remove());
  const before = svg.childNodes.length;
  drawCurve(svg, values.map((v, i) => [30 + i * 48, 90 - (v / 60) * 70]), seed);
  for (let i = before; i < svg.childNodes.length; i++) (svg.childNodes[i] as Element).setAttribute('data-sketched', '');
}

const painters: Record<string, (svg: SVGSVGElement, seed: number) => void> = { resonance, noise, meaning, eq };

export function drawArt(): void {
  for (const svg of document.querySelectorAll<SVGSVGElement>('svg[data-art]')) {
    const paint = painters[svg.dataset.art ?? ''];
    if (!paint) continue;
    paint(svg, randomSeed());
    svg.addEventListener('click', () => paint(svg, randomSeed()));
  }
}
