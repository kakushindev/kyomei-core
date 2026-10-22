// Checks the built site in dist/ before it ships: required files, internal links and anchors,
// nothing the Content-Security-Policy would block, and no names or identifiers that must not leak.
// Usage: node scripts/check-dist.mjs [distDir]
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, resolve, dirname } from 'node:path';

const dist = resolve(process.argv[2] ?? 'dist');
const problems = [];
const fail = (msg) => problems.push(msg);

if (!existsSync(dist)) {
  console.error(`check-dist: ${dist} does not exist; run npm run build first`);
  process.exit(1);
}

const walk = (dir) =>
  readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    return statSync(path).isDirectory() ? walk(path) : [path];
  });
const files = walk(dist);
const rel = (p) => relative(dist, p);

// ── Required files ─────────────────────────────────────────────────────────
const required = [
  'index.html', '404.html', 'robots.txt', 'sitemap-index.xml', 'og.png', 'favicon.svg',
  'apple-touch-icon.png', 'site.webmanifest', 'theme.js',
];
for (const name of required) if (!existsSync(join(dist, name))) fail(`missing ${name}`);
if (!files.some((f) => rel(f).startsWith('_assets/') && f.endsWith('.css'))) fail('no stylesheet in _assets/');
if (!files.some((f) => rel(f).startsWith('_assets/') && f.endsWith('.js'))) fail('no script in _assets/');

// ── Pages ──────────────────────────────────────────────────────────────────
const html = files.filter((f) => f.endsWith('.html'));
const idsByPage = new Map(
  html.map((f) => [f, new Set([...readFileSync(f, 'utf8').matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]))]),
);

const resolveTarget = (page, url) => {
  const clean = url.split(/[?#]/)[0];
  if (clean === '') return page;
  const base = clean.startsWith('/') ? join(dist, clean) : join(dirname(page), clean);
  if (existsSync(base) && statSync(base).isFile()) return base;
  if (existsSync(join(base, 'index.html'))) return join(base, 'index.html');
  if (existsSync(`${base}.html`)) return `${base}.html`;
  return null;
};

for (const page of html) {
  const source = readFileSync(page, 'utf8');
  const name = rel(page);

  for (const m of source.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)) {
    const [, attrs, body] = m;
    const type = /type="([^"]+)"/.exec(attrs)?.[1];
    if (type === 'application/ld+json') {
      try { JSON.parse(body); } catch { fail(`${name}: JSON-LD does not parse`); }
    } else if (!/\ssrc="/.test(attrs) || body.trim() !== '') {
      fail(`${name}: inline script (blocked by script-src 'self')`);
    }
  }
  if (/<style\b/.test(source)) fail(`${name}: inline <style> element (blocked by style-src 'self')`);
  for (const m of source.matchAll(/\s(on[a-z]+)=["']/g)) fail(`${name}: inline event handler ${m[1]}`);
  if (/\bhref="javascript:/i.test(source)) fail(`${name}: javascript: URL`);
  if (!/<html lang="/.test(source)) fail(`${name}: <html> has no lang`);
  if (!/<title>[^<]+<\/title>/.test(source)) fail(`${name}: no <title>`);

  for (const m of source.matchAll(/<img\b[^>]*>/g)) {
    if (!/\salt="/.test(m[0])) fail(`${name}: <img> without alt: ${m[0].slice(0, 80)}`);
    if (!/\swidth="\d+"/.test(m[0]) || !/\sheight="\d+"/.test(m[0])) fail(`${name}: <img> without width/height`);
  }

  for (const m of source.matchAll(/\s(?:href|src)="([^"]+)"/g)) {
    const url = m[1];
    if (/^(https?:|mailto:|data:)/.test(url)) {
      if (url.startsWith('http:')) fail(`${name}: insecure link ${url}`);
      continue;
    }
    const target = resolveTarget(page, url);
    if (!target) { fail(`${name}: broken link ${url}`); continue; }
    const hash = url.split('#')[1];
    if (hash && target.endsWith('.html') && !idsByPage.get(target)?.has(hash)) fail(`${name}: missing anchor ${url}`);
  }
}

// CSS url() references (fonts, images) must exist.
for (const css of files.filter((f) => f.endsWith('.css'))) {
  for (const m of readFileSync(css, 'utf8').matchAll(/url\(\s*["']?([^"')]+)["']?\s*\)/g)) {
    const url = m[1];
    if (/^(data:|https?:|#)/.test(url)) continue;
    const target = url.startsWith('/') ? join(dist, url) : join(dirname(css), url);
    if (!existsSync(target.split(/[?#]/)[0])) fail(`${rel(css)}: missing ${url}`);
  }
}

// ── Things that must never ship ────────────────────────────────────────────
const textFiles = files.filter((f) => /\.(html|css|js|xml|txt|json|webmanifest|svg)$/.test(f));
const forbidden = [
  [/CoreBuds/i, 'old product name'],
  [/kyomei-macos/, 'old repository name'],
  [/\b(?:[0-9A-F]{2}[:-]){5}[0-9A-F]{2}\b/i, 'something shaped like a Bluetooth address'],
  [/\b(?:ghp|gho|github_pat)_[A-Za-z0-9_]{20,}/, 'GitHub token'],
  [/innerHTML\s*=/, 'innerHTML assignment'],
];
for (const file of textFiles) {
  const source = readFileSync(file, 'utf8');
  for (const [pattern, what] of forbidden) {
    if (pattern.test(source)) fail(`${rel(file)}: contains ${what}`);
  }
}

const bytes = files.reduce((sum, f) => sum + statSync(f).size, 0);
if (problems.length > 0) {
  console.error(`check-dist: ${problems.length} problem(s)\n  - ${problems.join('\n  - ')}`);
  process.exit(1);
}
console.log(`check-dist: OK (${files.length} files, ${html.length} pages, ${(bytes / 1024).toFixed(0)} KiB)`);
